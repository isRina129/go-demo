package main

import (
	"fmt"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/isrina129/go-demo/internal/webapp"
)

func registerRoutes(group *gin.RouterGroup) {
	group.GET("/users/:user_id", func(c *gin.Context) {
		userID := c.Param("user_id")
		c.JSON(http.StatusOK, gin.H{
			"id":      userID,
			"name":    "FC DevOps User",
			"email":   fmt.Sprintf("%s@example.com", userID),
			"message": fmt.Sprintf("user %s is served by the user service", userID),
		})
	})
}

func main() {
	if err := webapp.Run(webapp.Config{ServiceKey: "user", Name: "User API"}, registerRoutes); err != nil {
		log.Fatal(err)
	}
}
