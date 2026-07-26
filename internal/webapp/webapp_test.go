package webapp

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestNewRouter(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := NewRouter(Config{ServiceKey: "demo", Name: "Demo API"}, func(group *gin.RouterGroup) {
		group.GET("/ping", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{"message": "pong"})
		})
	})
	for _, path := range []string{"/", "/health", "/api/v1/ping"} {
		request := httptest.NewRequest(http.MethodGet, path, nil)
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		if response.Code != http.StatusOK {
			t.Fatalf("%s returned %d", path, response.Code)
		}
		if response.Header().Get("X-Demo-Service") != "demo" {
			t.Fatalf("%s did not return the service header", path)
		}
	}
}
