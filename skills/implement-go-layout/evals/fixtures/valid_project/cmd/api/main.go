package main

import (
	"example.com/api/internal/platform/database"
	"example.com/api/internal/server"
)

func main() {
	db := database.Connect()
	srv := server.New(db)
	_ = srv.Run(":8080")
}
