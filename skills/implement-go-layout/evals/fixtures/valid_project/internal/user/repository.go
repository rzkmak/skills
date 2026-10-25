package user

import (
	"database/sql"
)

// Repository encapsulates persistence for the user domain.
type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) All() []User {
	rows, err := r.db.Query("SELECT id, name, email FROM users")
	if err != nil {
		return nil
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var u User
		_ = rows.Scan(&u.ID, &u.Name, &u.Email)
		users = append(users, u)
	}
	return users
}
