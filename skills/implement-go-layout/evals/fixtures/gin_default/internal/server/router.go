package server

import (
	"github.com/gin-gonic/gin"

	"example.com/api/internal/user"
)

// ANTIATTERN: gin.Default() hides the middleware chain.
func New() *gin.Engine {
	r := gin.Default()
	api := r.Group("/api/v1")
	user.RegisterUserRoutes(api)
	return r
}
