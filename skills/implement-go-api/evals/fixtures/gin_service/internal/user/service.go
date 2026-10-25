package user

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func RegisterUserRoutes(rg *gin.RouterGroup) {
	rg.GET("/users", list)
}

// ANTIATTERN: gin.Context (and gin) inside the service layer.
func list(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"users": []string{}})
}
