// GENERATED CODE - DO NOT MODIFY BY HAND.
//
// Source: users.proto
// Regenerate with: laska contract sdk --lang=go

package users

import (
	"context"

	"github.com/TenderOwl/laska/example/contract_slice/go/internal/grpc"
)

// UsersServiceClient is the client of the `users.v1.UsersService` service.
type UsersServiceClient struct {
	// conn is the connection to the server.
	conn *grpc.Conn
	// options are the options of the calls of the client.
	options CallOptions
}

// NewUsersServiceClient opens a connection to the service at [target].
//
// The target is a host and a port, e.g. `localhost:50051`.
func NewUsersServiceClient(target string, opts ...CallOptions) (*UsersServiceClient, error) {
	options := CallOptions{}
	if len(opts) > 0 {
		options = opts[0]
	}
	conn, err := grpc.Dial(target, options.Timeout)
	if err != nil {
		return nil, err
	}
	return &UsersServiceClient{conn: conn, options: options}, nil
}

// Close closes the connection of the client.
func (c *UsersServiceClient) Close() error {
	return c.conn.Close()
}

// GetUser calls the `GetUser` method of the service.
func (c *UsersServiceClient) GetUser(ctx context.Context, request *GetUserRequest, opts ...CallOptions) (*User, error) {
	options := c.options
	if len(opts) > 0 {
		options = opts[0]
	}
	if options.Timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, options.Timeout)
		defer cancel()
	}
	raw, err := c.conn.Invoke(ctx, "/users.v1.UsersService/GetUser", request.MarshalProto(), options.Metadata)
	if err != nil {
		return nil, err
	}
	response := &User{}
	if err := response.UnmarshalProto(raw); err != nil {
		return nil, err
	}
	return response, nil
}

// ListUsers calls the `ListUsers` method of the service.
func (c *UsersServiceClient) ListUsers(ctx context.Context, request *ListUsersRequest, opts ...CallOptions) (*ListUsersResponse, error) {
	options := c.options
	if len(opts) > 0 {
		options = opts[0]
	}
	if options.Timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, options.Timeout)
		defer cancel()
	}
	raw, err := c.conn.Invoke(ctx, "/users.v1.UsersService/ListUsers", request.MarshalProto(), options.Metadata)
	if err != nil {
		return nil, err
	}
	response := &ListUsersResponse{}
	if err := response.UnmarshalProto(raw); err != nil {
		return nil, err
	}
	return response, nil
}

// CreateUser calls the `CreateUser` method of the service.
func (c *UsersServiceClient) CreateUser(ctx context.Context, request *CreateUserRequest, opts ...CallOptions) (*User, error) {
	options := c.options
	if len(opts) > 0 {
		options = opts[0]
	}
	if options.Timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, options.Timeout)
		defer cancel()
	}
	raw, err := c.conn.Invoke(ctx, "/users.v1.UsersService/CreateUser", request.MarshalProto(), options.Metadata)
	if err != nil {
		return nil, err
	}
	response := &User{}
	if err := response.UnmarshalProto(raw); err != nil {
		return nil, err
	}
	return response, nil
}
