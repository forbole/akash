package manifest

import (
	"context"
	"errors"
	"time"

	"github.com/ovrclk/akash/provider/cluster"

	"github.com/boz/go-lifecycle"

	"github.com/ovrclk/akash/manifest"

	"github.com/ovrclk/akash/provider/event"
	"github.com/ovrclk/akash/provider/session"
	"github.com/ovrclk/akash/pubsub"
	dquery "github.com/ovrclk/akash/x/deployment/query"
	dtypes "github.com/ovrclk/akash/x/deployment/types"
	mtypes "github.com/ovrclk/akash/x/market/types"
)

// ErrNotRunning is the error when service is not running
var ErrNotRunning = errors.New("not running")

// StatusClient is the interface which includes status of service
type StatusClient interface {
	Status(context.Context) (*Status, error)
}

// Handler is the interface that wraps HandleManifest method
type Client interface {
	Submit(context.Context, dtypes.DeploymentID, manifest.Manifest) error
}

// Service is the interface that includes StatusClient and Handler interfaces. It also wraps Done method
type Service interface {
	StatusClient
	Client
	Done() <-chan struct{}
}

// NewHandler creates and returns new Service instance
// Manage incoming leases and manifests and pair the two together to construct and emit a ManifestReceived event.
func NewService(ctx context.Context, session session.Session, bus pubsub.Bus, hostnameService cluster.HostnameServiceClient, cfg ServiceConfig) (Service, error) {
	session = session.ForModule("provider-manifest")

	sub, err := bus.Subscribe()
	if err != nil {
		return nil, err
	}

	leases, err := fetchExistingLeases(ctx, session)
	if err != nil {
		session.Log().Error("fetching existing leases", "err", err)
		sub.Close()
		return nil, err
	}
	session.Log().Info("found existing leases", "count", len(leases))

	s := &service{
		session:         session,
		bus:             bus,
		sub:             sub,
		statusch:        make(chan chan<- *Status),
		mreqch:          make(chan manifestRequest),
		managers:        make(map[string]*manager),
		managerch:       make(chan *manager),
		lc:              lifecycle.New(),
		hostnameService: hostnameService,
		config:          cfg,

		watchdogch: make(chan dtypes.DeploymentID),
		watchdogs:  make(map[dtypes.DeploymentID]*watchdog),
	}

	go s.lc.WatchContext(ctx)
	go s.run(leases)

	return s, nil
}

type service struct {
	config  ServiceConfig
	session session.Session
	bus     pubsub.Bus
	sub     pubsub.Subscriber
	lc      lifecycle.Lifecycle

	statusch chan chan<- *Status
	mreqch   chan manifestRequest

	managers  map[string]*manager
	managerch chan *manager

	hostnameService cluster.HostnameServiceClient

	watchdogs  map[dtypes.DeploymentID]*watchdog
	watchdogch chan dtypes.DeploymentID
}

type manifestRequest struct {
	value *submitRequest
	ch    chan<- error
	ctx   context.Context
}

// Send incoming manifest request.
func (s *service) Submit(ctx context.Context, did dtypes.DeploymentID, mani manifest.Manifest) error {
	ch := make(chan error, 1)
	req := manifestRequest{
		value: &submitRequest{
			Deployment: did,
			Manifest:   mani,
		},
		ch:  ch,
		ctx: ctx,
	}

	select {
	case <-ctx.Done():
		return ctx.Err()
	case s.mreqch <- req:
	case <-s.lc.ShuttingDown():
		return ErrNotRunning
	case <-s.lc.Done():
		return ErrNotRunning
	}

	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-s.lc.Done():
		return ErrNotRunning
	case result := <-ch:
		return result
	}
}

func (s *service) Done() <-chan struct{} {
	return s.lc.Done()
}

func (s *service) Status(ctx context.Context) (*Status, error) {
	ch := make(chan *Status, 1)

	select {
	case <-s.lc.Done():
		return nil, ErrNotRunning
	case <-ctx.Done():
		return nil, ctx.Err()
	case s.statusch <- ch:
	}

	select {
	case <-s.lc.Done():
		return nil, ErrNotRunning
	case <-ctx.Done():
		return nil, ctx.Err()
	case result := <-ch:
		return result, nil
	}
}

func (s *service) run(leases []event.LeaseWon) {
	defer s.lc.ShutdownCompleted()
	defer s.sub.Close()

	s.managePreExistingLease(leases)

loop:
	for {
		select {

		case err := <-s.lc.ShutdownRequest():
			s.lc.ShutdownInitiated(err)
			break loop

		case ev := <-s.sub.Events():
			switch ev := ev.(type) {

			case event.LeaseWon:
				s.session.Log().Info("lease won", "lease", ev.LeaseID)

				s.handleLease(ev)

			case dtypes.EventDeploymentUpdated:
				s.session.Log().Info("update received", "deployment", ev.ID, "version", ev.Version)

				key := dquery.DeploymentPath(ev.ID)
				if manager := s.managers[key]; manager != nil {
					s.session.Log().Info("deployment updated", "deployment", ev.ID, "version", ev.Version)
					manager.handleUpdate(ev.Version)
				}

			case dtypes.EventDeploymentClosed:

				key := dquery.DeploymentPath(ev.ID)
				if manager := s.managers[key]; manager != nil {
					s.session.Log().Info("deployment closed", "deployment", ev.ID)
					manager.stop()
				}

			case mtypes.EventLeaseClosed:
				if ev.ID.Provider != s.session.Provider().Address().String() {
					continue
				}

				key := dquery.DeploymentPath(ev.ID.DeploymentID())
				if manager := s.managers[key]; manager != nil {
					s.session.Log().Info("lease closed", "lease", ev.ID)
					manager.removeLease(ev.ID)
				}
			}

		case req := <-s.mreqch:
			// Cancel the watchdog (if it exists), since a manifest has been received
			s.maybeRemoveWatchdog(req.value.Deployment)

			manager, err := s.ensureManager(req.value.Deployment)
			if err != nil {
				s.session.Log().Error("error fetching manager for manifest",
					"err", err, "deployment", req.value.Deployment)
				req.ch <- err
				break
			}
			// The manager is responsible for putting a result in req.ch
			manager.handleManifest(req)

		case ch := <-s.statusch:

			ch <- &Status{
				Deployments: uint32(len(s.managers)),
			}

		case manager := <-s.managerch:
			s.session.Log().Info("manager done", "deployment", manager.daddr)

			delete(s.managers, dquery.DeploymentPath(manager.daddr))

			// Cancel the watchdog (if it exists) since the manager has stopped as well
			s.maybeRemoveWatchdog(manager.daddr)

		case leaseID := <-s.watchdogch:
			s.session.Log().Info("watchdog done", "lease", leaseID)
			delete(s.watchdogs, leaseID)
		}
	}

	for len(s.managers) > 0 {
		manager := <-s.managerch
		delete(s.managers, dquery.DeploymentPath(manager.daddr))
	}

	s.session.Log().Debug("draining watchdogs", "qty", len(s.watchdogs))
	for _, watchdog := range s.watchdogs {
		if watchdog != nil {
			leaseID := <-s.watchdogch
			s.session.Log().Info("watchdog done", "lease", leaseID)
		}
	}

}

func (s *service) maybeRemoveWatchdog(deploymentID dtypes.DeploymentID) {
	if watchdog := s.watchdogs[deploymentID]; watchdog != nil {
		watchdog.stop()
	}
}

func (s *service) managePreExistingLease(leases []event.LeaseWon) {
	for _, lease := range leases {
		s.handleLease(lease)
	}
}

func (s *service) handleLease(ev event.LeaseWon) {
	// Only run this if configured to do so
	if s.config.ManifestTimeout > time.Duration(0) {
		// Create watchdog if it does not exist AND a manifest has not been received yet
		if watchdog := s.watchdogs[ev.LeaseID.DeploymentID()]; watchdog == nil {
			watchdog = newWatchdog(s.session, s.lc.ShuttingDown(), s.watchdogch, ev.LeaseID, s.config.ManifestTimeout)
			s.watchdogs[ev.LeaseID.DeploymentID()] = watchdog
		}
	}

	manager, err := s.ensureManager(ev.LeaseID.DeploymentID())
	if err != nil {
		s.session.Log().Error("error creating manager",
			"err", err, "lease", ev.LeaseID)
		return
	}

	manager.handleLease(ev)
}

func (s *service) ensureManager(did dtypes.DeploymentID) (manager *manager, err error) {
	manager = s.managers[dquery.DeploymentPath(did)]
	if manager == nil {
		manager, err = newManager(s, did)
		if err != nil {
			return nil, err
		}
		s.managers[dquery.DeploymentPath(did)] = manager
	}
	return manager, nil
}

func fetchExistingLeases(ctx context.Context, session session.Session) ([]event.LeaseWon, error) {
	leases, err := session.Client().Query().ActiveLeasesForProvider(session.Provider().Address())
	if err != nil {
		return nil, err
	}

	items := make([]event.LeaseWon, 0, len(leases))
	for _, lease := range leases {
		res, err := session.Client().Query().Group(
			ctx,
			&dtypes.QueryGroupRequest{
				ID: lease.Lease.LeaseID.GroupID(),
			},
		)
		if err != nil {
			session.Log().Error("can't fetch deployment group", "err", err, "lease", lease)
			continue
		}
		dgroup := res.Group

		items = append(items, event.LeaseWon{
			LeaseID: lease.Lease.LeaseID,
			Price:   lease.Lease.Price,
			Group:   &dgroup,
		})
	}

	session.Log().Debug("fetching leases", "lease-count", len(items))

	return items, nil
}
