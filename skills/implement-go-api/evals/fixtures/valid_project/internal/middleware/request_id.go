package middleware

import (
	"github.com/gin-gonic/gin"
)

// RequestID attaches a per-request identifier to the context.
func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.GetHeader("X-Request-Id")
		if id == "" {
			id = "generated"
		}
		c.Set("request_id", id)
		c.Next()
	}
}
