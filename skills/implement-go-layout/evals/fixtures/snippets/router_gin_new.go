package server

import (
	"github.com/gin-gonic/gin"

	"example.com/api/internal/user"
)

// Valid router: gin.New() with an explicit middleware chain.
func NewRouter() *gin.Engine {
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())
	api := r.Group("/api/v1")
	user.RegisterUserRoutes(api)
	return r
}
