package user

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// Valid handler: ShouldBind* family, DTO with binding tags.
type CreateUserRequest struct {
	Username string `json:"username" binding:"required,alphanum,min=3,max=30"`
	Email    string `json:"email" binding:"required,email"`
}

func create(c *gin.Context) {
	var req CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"username": req.Username})
}
