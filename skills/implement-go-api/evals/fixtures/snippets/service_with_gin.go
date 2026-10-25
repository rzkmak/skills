package user

import (
	"github.com/gin-gonic/gin"
)

// Antipattern: gin.Context inside the service layer.
func ListActive(c *gin.Context) []string {
	return []string{}
}
