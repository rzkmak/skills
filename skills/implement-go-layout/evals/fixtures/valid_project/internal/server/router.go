package server

import (
	"github.com/gin-gonic/gin"

	"example.com/api/internal/middleware"
	"example.com/api/internal/user"
)

func NewRouter() *gin.Engine {
	r := gin.New()

	// Global middleware — explicit chain, no convenience defaults.
	r.Use(gin.Logger(), gin.Recovery())
	r.Use(middleware.RequestID())

	api := r.Group("/api/v1")
	user.RegisterUserRoutes(api)

	return r
}
