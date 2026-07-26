package webapp

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
)

var (
	Version   = "dev"
	CommitSHA = "unknown"
	BuildTime = "unknown"
)

type Config struct {
	ServiceKey string
	Name       string
}

type RouteRegistrar func(group *gin.RouterGroup)

func NewRouter(config Config, register RouteRegistrar) *gin.Engine {
	engine := gin.New()
	engine.Use(gin.Recovery())
	engine.Use(func(c *gin.Context) {
		c.Header("X-Demo-Service", config.ServiceKey)
		c.Header("X-Demo-Version", Version)
		c.Next()
	})
	engine.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"service":    config.ServiceKey,
			"name":       config.Name,
			"version":    Version,
			"commit_sha": CommitSHA,
			"build_time": BuildTime,
		})
	})
	engine.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": config.ServiceKey})
	})
	api := engine.Group("/api/v1")
	register(api)
	return engine
}

func Run(config Config, register RouteRegistrar) error {
	if strings.TrimSpace(config.ServiceKey) == "" {
		return fmt.Errorf("service key is required")
	}
	if os.Getenv("APP_ENV") != "development" {
		gin.SetMode(gin.ReleaseMode)
	}
	server := &http.Server{
		Addr:              ":" + serverPort(),
		Handler:           NewRouter(config, register),
		ReadHeaderTimeout: 5 * time.Second,
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	errCh := make(chan error, 1)
	go func() {
		errCh <- server.ListenAndServe()
	}()
	select {
	case err := <-errCh:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return server.Shutdown(shutdownCtx)
	}
}

func serverPort() string {
	for _, key := range []string{"PORT", "FC_SERVER_PORT"} {
		value := strings.TrimSpace(os.Getenv(key))
		if port, err := strconv.Atoi(value); err == nil && port > 0 && port <= 65535 {
			return strconv.Itoa(port)
		}
	}
	return "9000"
}
