package server

import (
	"github.com/gin-gonic/gin"

	"example.com/api/internal/user"
)

func New() *gin.Engine {
	r := gin.New()
	r.Use(gin.Recovery())
	api := r.Group("/api/v1")
	user.RegisterUserRoutes(api)
	return r
}
