package user

// CreateUserRequest is the transport DTO for creating a user.
// Validation tags live here, never on the domain model.
type CreateUserRequest struct {
	Username string `json:"username" binding:"required,alphanum,min=3,max=30"`
	Email    string `json:"email" binding:"required,email"`
	Age      int    `json:"age" binding:"gte=1,lte=130"`
}

// UserResponse is the transport DTO returned to clients.
type UserResponse struct {
	ID    uint   `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
}
