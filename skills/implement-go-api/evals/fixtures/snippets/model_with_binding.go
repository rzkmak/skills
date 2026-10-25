package user

// Antipattern: transport validation tags on the domain model.
type User struct {
	ID       uint   `binding:"required"`
	Username string `binding:"required,alphanum"`
	Email    string `binding:"required,email"`
}
