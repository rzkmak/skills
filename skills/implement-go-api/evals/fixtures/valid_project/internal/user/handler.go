package user

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// Handler is the transport layer for the user domain.
type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

// RegisterUserRoutes registers all user endpoints on the given group.
func RegisterUserRoutes(rg *gin.RouterGroup, h *Handler) {
	rg.GET("/users", h.list)
	rg.POST("/users", h.create)
	rg.GET("/users/:id", h.get)
}

func (h *Handler) create(c *gin.Context) {
	var req CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"email": req.Email})
}

func (h *Handler) list(c *gin.Context) {
	c.JSON(http.StatusOK, h.svc.List())
}

func (h *Handler) get(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"id": c.Param("id")})
}
