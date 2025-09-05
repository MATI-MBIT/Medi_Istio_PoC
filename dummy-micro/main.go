package main

import (
	"encoding/json"
	"log"
	"net/http"
)

type PurchaseResponse struct {
	ID      string  `json:"id"`
	Item    string  `json:"item"`
	Amount  float64 `json:"amount"`
	Status  string  `json:"status"`
	Message string  `json:"message"`
}

func pingHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "text/plain")
	w.Write([]byte("pong\n"))
}

func purchaseHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	response := PurchaseResponse{
		ID:      "123e4567-e89b-12d3-a456-426614174000",
		Item:    "Sample Product",
		Amount:  99.99,
		Status:  "completed",
		Message: "Purchase processed successfully",
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func main() {
	http.HandleFunc("/v1/ping", pingHandler)
	http.HandleFunc("/v1/purchase", purchaseHandler)

	port := ":8080"
	log.Printf("Server starting on port %s\n", port)
	log.Fatal(http.ListenAndServe(port, nil))
}
