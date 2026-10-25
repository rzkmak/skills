package main

import (
	"example.com/api/internal/server"
)

func main() {
	srv := server.New()
	_ = srv.Run(":8080")
}
