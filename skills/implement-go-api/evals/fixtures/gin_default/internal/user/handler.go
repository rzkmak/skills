package user

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func RegisterUserRoutes(rg *gin.RouterGroup) {
	rg.POST("/users", create)
}

func create(c *gin.Context) {
	c.JSON(http.StatusCreated, gin.H{"ok": true})
}
