package user

import (
	"github.com/gin-gonic/gin"
)

// Antipattern: auto-aborting Bind* instead of ShouldBind*.
type CreateUserRequest struct {
	Username string `json:"username" binding:"required"`
}

func create(c *gin.Context) {
	var req CreateUserRequest
	if err := c.BindJSON(&req); err != nil {
		return
	}
	c.JSON(201, gin.H{"ok": true})
}
