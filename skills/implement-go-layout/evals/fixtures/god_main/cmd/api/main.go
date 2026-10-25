package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// ANTIATTERN: all routes and handlers crammed into main.go.

func createUser(c *gin.Context) {
	c.JSON(http.StatusCreated, gin.H{"ok": true})
}

func main() {
	r := gin.New()
	r.POST("/api/v1/users", createUser)
	_ = r.Run(":8080")
}
