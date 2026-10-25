package user

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type CreateUserRequest struct {
	Username string `json:"username" binding:"required"`
}

func RegisterUserRoutes(rg *gin.RouterGroup) {
	rg.POST("/users", create)
}

// ANTIATTERN: c.BindJSON aborts with 400 before the handler can shape the error.
func create(c *gin.Context) {
	var req CreateUserRequest
	if err := c.BindJSON(&req); err != nil {
		return
	}
	c.JSON(http.StatusCreated, gin.H{"ok": true})
}
