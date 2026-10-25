package user

// Service holds the user business logic. Dependencies are constructor-injected;
// no framework context, no global state.
type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// List returns all users. Business logic belongs here, not in handlers.
func (s *Service) List() []User {
	return s.repo.All()
}
