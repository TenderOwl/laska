// The program calls the service of the example over gRPC and prints what it
// got as JSON, so the test of the example may check the answer of the service.
//
// The program is the end of the journey of the SDK of Go: it holds the
// generated client, opens the connection and calls the methods of the
// contract.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"time"

	users "github.com/TenderOwl/laska/example/contract_slice/go"
)

// The answer of the service, as the test of the example reads it.
type answer struct {
	Id          string   `json:"id"`
	Email       string   `json:"email"`
	DisplayName string   `json:"displayName"`
	Role        string   `json:"role"`
	Tags        []string `json:"tags"`
	CreatedAt   int64    `json:"createdAt"`
	Users       int      `json:"users"`
	MissingCode int      `json:"missingCode"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "the program needs the address of the service")
		os.Exit(64)
	}

	client, err := users.NewUsersServiceClient(
		os.Args[1],
		users.CallOptions{Timeout: 10 * time.Second},
	)
	if err != nil {
		fmt.Fprintln(os.Stderr, "the client does not open the connection:", err)
		os.Exit(1)
	}
	defer client.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	user, err := client.GetUser(ctx, &users.GetUserRequest{Id: "u_1"})
	if err != nil {
		fmt.Fprintln(os.Stderr, "the call of the service fails:", err)
		os.Exit(1)
	}

	list, err := client.ListUsers(ctx, &users.ListUsersRequest{Limit: 10})
	if err != nil {
		fmt.Fprintln(os.Stderr, "the call of the service fails:", err)
		os.Exit(1)
	}

	result := answer{
		Id:          user.Id,
		Email:       user.Email,
		DisplayName: user.DisplayName,
		Role:        user.Role.String(),
		Tags:        user.Tags,
		Users:       len(list.Users),
	}
	if user.CreatedAt != nil {
		result.CreatedAt = user.CreatedAt.Seconds
	}

	if _, err := client.GetUser(ctx, &users.GetUserRequest{Id: "nope"}); err != nil {
		var status *users.StatusError
		if !errors.As(err, &status) {
			fmt.Fprintln(os.Stderr, "the failure of the call is not a status:", err)
			os.Exit(1)
		}
		result.MissingCode = status.Code
	}

	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		fmt.Fprintln(os.Stderr, "the answer is not written:", err)
		os.Exit(1)
	}
}
