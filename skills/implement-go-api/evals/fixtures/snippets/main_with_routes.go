package main

import (
	"github.com/gin-gonic/gin"
)

// Antipattern: route registration in main.go.
func main() {
	r := gin.New()
	r.POST("/api/v1/users", func(c *gin.Context) {})
	_ = r.Run(":8080")
}
