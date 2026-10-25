package user

// User is the domain model. Transport concerns (JSON shape, validation tags)
// belong in dto.go, not here.
type User struct {
	ID    uint
	Name  string
	Email string
}
