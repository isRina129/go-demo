package main

import (
	"fmt"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/isrina129/go-demo/internal/webapp"
)

func registerRoutes(group *gin.RouterGroup) {
	group.GET("/orders/:order_id", func(c *gin.Context) {
		orderID := c.Param("order_id")
		c.JSON(http.StatusOK, gin.H{
			"id":      orderID,
			"status":  "PAID-HHHHH",
			"amount":  199.00,
			"message": fmt.Sprintf("order %s is served by the order service", orderID),
		})
	})
}

func main() {
	if err := webapp.Run(webapp.Config{ServiceKey: "order", Name: "Order API"}, registerRoutes); err != nil {
		log.Fatal(err)
	}
}
