// GENERATED CODE - DO NOT MODIFY BY HAND.
//
// Source: users.proto
// Regenerate with: laska contract sdk --lang=go

package users

import (
	"fmt"
	"io"

	"github.com/TenderOwl/laska/example/contract_slice/go/internal/wire"
)

// UserRole is the role a user has.
type UserRole int32

const (
	// UserRoleUnspecified is the value USER_ROLE_UNSPECIFIED of the enum.
	UserRoleUnspecified UserRole = 0
	// UserRoleAdmin is the value USER_ROLE_ADMIN of the enum.
	UserRoleAdmin UserRole = 1
	// UserRoleMember is the value USER_ROLE_MEMBER of the enum.
	UserRoleMember UserRole = 2
)

// String returns the name of the value of the enum.
func (e UserRole) String() string {
	switch e {
	case UserRoleUnspecified:
		return "USER_ROLE_UNSPECIFIED"
	case UserRoleAdmin:
		return "USER_ROLE_ADMIN"
	case UserRoleMember:
		return "USER_ROLE_MEMBER"
	default:
		return fmt.Sprintf("UserRole(%d)", int(e))
	}
}

// SubscriptionState is the state of the subscription.
type SubscriptionState int32

const (
	// SubscriptionStateActive is the value SUBSCRIPTION_STATE_ACTIVE of the enum.
	SubscriptionStateActive SubscriptionState = 0
	// SubscriptionStatePaused is the value SUBSCRIPTION_STATE_PAUSED of the enum.
	SubscriptionStatePaused SubscriptionState = 1
)

// String returns the name of the value of the enum.
func (e SubscriptionState) String() string {
	switch e {
	case SubscriptionStateActive:
		return "SUBSCRIPTION_STATE_ACTIVE"
	case SubscriptionStatePaused:
		return "SUBSCRIPTION_STATE_PAUSED"
	default:
		return fmt.Sprintf("SubscriptionState(%d)", int(e))
	}
}

// User is a user of the application.
type User struct {
	// Id is the stable identifier of the user.
	Id string
	// Email is the email address of the user.
	Email string
	// DisplayName is the human readable name.
	DisplayName string
	// Role is the role of the user.
	Role UserRole
	// Tags is the free form tags.
	Tags []string
	// CreatedAt is the moment the account was created.
	CreatedAt *ProtoTimestamp
}

// MarshalProto writes the message on the wire.
func (m *User) MarshalProto() []byte {
	w := wire.NewWriter()
	if m.Id != "" {
		w.WriteString(1, m.Id)
	}
	if m.Email != "" {
		w.WriteString(2, m.Email)
	}
	if m.DisplayName != "" {
		w.WriteString(3, m.DisplayName)
	}
	if m.Role != 0 {
		w.WriteEnum(4, int32(m.Role))
	}
	for _, value := range m.Tags {
		w.WriteString(5, value)
	}
	if m.CreatedAt != nil {
		w.WriteMessage(6, m.CreatedAt)
	}
	return w.Bytes()
}

// UnmarshalProto reads the message out of its bytes.
func (m *User) UnmarshalProto(data []byte) error {
	*m = User{}
	r := wire.NewReader(data)
	for {
		field, typ, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		switch field {
		case 1:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadString()
			if err != nil {
				return err
			}
			m.Id = value
		case 2:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadString()
			if err != nil {
				return err
			}
			m.Email = value
		case 3:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadString()
			if err != nil {
				return err
			}
			m.DisplayName = value
		case 4:
			if typ != wire.TypeVarint {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			number, err := r.ReadEnum()
			if err != nil {
				return err
			}
			m.Role = UserRole(number)
		case 5:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadString()
			if err != nil {
				return err
			}
			m.Tags = append(m.Tags, value)
		case 6:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			data, err := r.ReadBytes()
			if err != nil {
				return err
			}
			item := &ProtoTimestamp{}
			if err := item.UnmarshalProto(data); err != nil {
				return err
			}
			m.CreatedAt = item
		default:
			if err := r.Skip(typ); err != nil {
				return err
			}
		}
	}
	return nil
}

// GetId returns the value of the field.
func (m *User) GetId() string {
	if m == nil {
		return ""
	}
	return m.Id
}

// GetEmail returns the value of the field.
func (m *User) GetEmail() string {
	if m == nil {
		return ""
	}
	return m.Email
}

// GetDisplayName returns the value of the field.
func (m *User) GetDisplayName() string {
	if m == nil {
		return ""
	}
	return m.DisplayName
}

// GetRole returns the value of the field.
func (m *User) GetRole() UserRole {
	if m == nil {
		return UserRole(0)
	}
	return m.Role
}

// GetTags returns the value of the field.
func (m *User) GetTags() []string {
	if m == nil {
		return nil
	}
	return m.Tags
}

// GetCreatedAt returns the value of the field.
func (m *User) GetCreatedAt() *ProtoTimestamp {
	if m == nil {
		return nil
	}
	return m.CreatedAt
}

// GetUserRequest is the request of the GetUser method.
type GetUserRequest struct {
	// Id holds the value of the field "id".
	Id string
}

// MarshalProto writes the message on the wire.
func (m *GetUserRequest) MarshalProto() []byte {
	w := wire.NewWriter()
	if m.Id != "" {
		w.WriteString(1, m.Id)
	}
	return w.Bytes()
}

// UnmarshalProto reads the message out of its bytes.
func (m *GetUserRequest) UnmarshalProto(data []byte) error {
	*m = GetUserRequest{}
	r := wire.NewReader(data)
	for {
		field, typ, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		switch field {
		case 1:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadString()
			if err != nil {
				return err
			}
			m.Id = value
		default:
			if err := r.Skip(typ); err != nil {
				return err
			}
		}
	}
	return nil
}

// GetId returns the value of the field.
func (m *GetUserRequest) GetId() string {
	if m == nil {
		return ""
	}
	return m.Id
}

// ListUsersRequest is the request of the ListUsers method.
type ListUsersRequest struct {
	// Limit holds the value of the field "limit".
	Limit int32
	// Cursor holds the value of the field "cursor".
	Cursor string
}

// MarshalProto writes the message on the wire.
func (m *ListUsersRequest) MarshalProto() []byte {
	w := wire.NewWriter()
	if m.Limit != 0 {
		w.WriteInt32(1, m.Limit)
	}
	if m.Cursor != "" {
		w.WriteString(2, m.Cursor)
	}
	return w.Bytes()
}

// UnmarshalProto reads the message out of its bytes.
func (m *ListUsersRequest) UnmarshalProto(data []byte) error {
	*m = ListUsersRequest{}
	r := wire.NewReader(data)
	for {
		field, typ, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		switch field {
		case 1:
			if typ != wire.TypeVarint {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadInt32()
			if err != nil {
				return err
			}
			m.Limit = value
		case 2:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadString()
			if err != nil {
				return err
			}
			m.Cursor = value
		default:
			if err := r.Skip(typ); err != nil {
				return err
			}
		}
	}
	return nil
}

// GetLimit returns the value of the field.
func (m *ListUsersRequest) GetLimit() int32 {
	if m == nil {
		return 0
	}
	return m.Limit
}

// GetCursor returns the value of the field.
func (m *ListUsersRequest) GetCursor() string {
	if m == nil {
		return ""
	}
	return m.Cursor
}

// ListUsersResponse is the response of the ListUsers method.
type ListUsersResponse struct {
	// Users holds the value of the field "users".
	Users []*User
	// NextCursor holds the value of the field "next_cursor".
	NextCursor string
}

// MarshalProto writes the message on the wire.
func (m *ListUsersResponse) MarshalProto() []byte {
	w := wire.NewWriter()
	for _, value := range m.Users {
		w.WriteMessage(1, value)
	}
	if m.NextCursor != "" {
		w.WriteString(2, m.NextCursor)
	}
	return w.Bytes()
}

// UnmarshalProto reads the message out of its bytes.
func (m *ListUsersResponse) UnmarshalProto(data []byte) error {
	*m = ListUsersResponse{}
	r := wire.NewReader(data)
	for {
		field, typ, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		switch field {
		case 1:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			data, err := r.ReadBytes()
			if err != nil {
				return err
			}
			item := &User{}
			if err := item.UnmarshalProto(data); err != nil {
				return err
			}
			m.Users = append(m.Users, item)
		case 2:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadString()
			if err != nil {
				return err
			}
			m.NextCursor = value
		default:
			if err := r.Skip(typ); err != nil {
				return err
			}
		}
	}
	return nil
}

// GetUsers returns the value of the field.
func (m *ListUsersResponse) GetUsers() []*User {
	if m == nil {
		return nil
	}
	return m.Users
}

// GetNextCursor returns the value of the field.
func (m *ListUsersResponse) GetNextCursor() string {
	if m == nil {
		return ""
	}
	return m.NextCursor
}

// CreateUserRequest is the request of the CreateUser method.
type CreateUserRequest struct {
	// Email holds the value of the field "email".
	Email string
	// DisplayName holds the value of the field "display_name".
	DisplayName string
	// Role holds the value of the field "role".
	Role UserRole
}

// MarshalProto writes the message on the wire.
func (m *CreateUserRequest) MarshalProto() []byte {
	w := wire.NewWriter()
	if m.Email != "" {
		w.WriteString(1, m.Email)
	}
	if m.DisplayName != "" {
		w.WriteString(2, m.DisplayName)
	}
	if m.Role != 0 {
		w.WriteEnum(3, int32(m.Role))
	}
	return w.Bytes()
}

// UnmarshalProto reads the message out of its bytes.
func (m *CreateUserRequest) UnmarshalProto(data []byte) error {
	*m = CreateUserRequest{}
	r := wire.NewReader(data)
	for {
		field, typ, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		switch field {
		case 1:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadString()
			if err != nil {
				return err
			}
			m.Email = value
		case 2:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadString()
			if err != nil {
				return err
			}
			m.DisplayName = value
		case 3:
			if typ != wire.TypeVarint {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			number, err := r.ReadEnum()
			if err != nil {
				return err
			}
			m.Role = UserRole(number)
		default:
			if err := r.Skip(typ); err != nil {
				return err
			}
		}
	}
	return nil
}

// GetEmail returns the value of the field.
func (m *CreateUserRequest) GetEmail() string {
	if m == nil {
		return ""
	}
	return m.Email
}

// GetDisplayName returns the value of the field.
func (m *CreateUserRequest) GetDisplayName() string {
	if m == nil {
		return ""
	}
	return m.DisplayName
}

// GetRole returns the value of the field.
func (m *CreateUserRequest) GetRole() UserRole {
	if m == nil {
		return UserRole(0)
	}
	return m.Role
}

// Subscription is a subscription of a user to a plan.
// The message holds the constructs a contract needs the most: a message
// declared inside a message, an enum declared inside a message, a map and a
// group of a oneof.
type Subscription struct {
	// Plan is the plan of the subscription.
	Plan *SubscriptionPlan
	// State is the state of the subscription.
	State SubscriptionState
	// Features is the features of the plan, by their name.
	Features map[string]bool
	// CardToken holds the value of the field "card_token".
	CardToken *string
	// Iban holds the value of the field "iban".
	Iban *string
}

// MarshalProto writes the message on the wire.
func (m *Subscription) MarshalProto() []byte {
	w := wire.NewWriter()
	if m.Plan != nil {
		w.WriteMessage(1, m.Plan)
	}
	if m.State != 0 {
		w.WriteEnum(2, int32(m.State))
	}
	for key, value := range m.Features {
		entry := wire.NewWriter()
		entry.WriteString(1, key)
		entry.WriteBool(2, value)
		w.WriteBytes(3, entry.Bytes())
	}
	if m.CardToken != nil {
		w.WriteString(4, *m.CardToken)
	} else if m.Iban != nil {
		w.WriteString(5, *m.Iban)
	}
	return w.Bytes()
}

// UnmarshalProto reads the message out of its bytes.
func (m *Subscription) UnmarshalProto(data []byte) error {
	*m = Subscription{}
	r := wire.NewReader(data)
	for {
		field, typ, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		switch field {
		case 1:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			data, err := r.ReadBytes()
			if err != nil {
				return err
			}
			item := &SubscriptionPlan{}
			if err := item.UnmarshalProto(data); err != nil {
				return err
			}
			m.Plan = item
		case 2:
			if typ != wire.TypeVarint {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			number, err := r.ReadEnum()
			if err != nil {
				return err
			}
			m.State = SubscriptionState(number)
		case 3:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			entry, err := r.ReadBytes()
			if err != nil {
				return err
			}
			key, value, err := readSubscriptionFeaturesEntry(entry)
			if err != nil {
				return err
			}
			if m.Features == nil {
				m.Features = map[string]bool{}
			}
			m.Features[key] = value
		case 4:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadString()
			if err != nil {
				return err
			}
			m.CardToken = &value
			m.Iban = nil
		case 5:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadString()
			if err != nil {
				return err
			}
			m.Iban = &value
			m.CardToken = nil
		default:
			if err := r.Skip(typ); err != nil {
				return err
			}
		}
	}
	return nil
}

// GetPlan returns the value of the field.
func (m *Subscription) GetPlan() *SubscriptionPlan {
	if m == nil {
		return nil
	}
	return m.Plan
}

// GetState returns the value of the field.
func (m *Subscription) GetState() SubscriptionState {
	if m == nil {
		return SubscriptionState(0)
	}
	return m.State
}

// GetFeatures returns the value of the field.
func (m *Subscription) GetFeatures() map[string]bool {
	if m == nil {
		return nil
	}
	return m.Features
}

// GetCardToken returns the value of the field.
func (m *Subscription) GetCardToken() string {
	if m == nil || m.CardToken == nil {
		return ""
	}
	return *m.CardToken
}

// GetIban returns the value of the field.
func (m *Subscription) GetIban() string {
	if m == nil || m.Iban == nil {
		return ""
	}
	return *m.Iban
}

// readSubscriptionFeaturesEntry reads the entry of the map of the field "features" of the message.
func readSubscriptionFeaturesEntry(data []byte) (string, bool, error) {
	r := wire.NewReader(data)
	var key string
	var value bool
	for {
		field, typ, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return key, value, err
		}
		switch field {
		case 1:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return key, value, err
				}
				continue
			}
			text, err := r.ReadString()
			if err != nil {
				return key, value, err
			}
			key = text
		case 2:
			if typ != wire.TypeVarint {
				if err := r.Skip(typ); err != nil {
					return key, value, err
				}
				continue
			}
			text, err := r.ReadBool()
			if err != nil {
				return key, value, err
			}
			value = text
		default:
			if err := r.Skip(typ); err != nil {
				return key, value, err
			}
		}
	}
	return key, value, nil
}

// SubscriptionPlan is the plan of the subscription.
type SubscriptionPlan struct {
	// Name holds the value of the field "name".
	Name string
	// Seats holds the value of the field "seats".
	Seats int32
}

// MarshalProto writes the message on the wire.
func (m *SubscriptionPlan) MarshalProto() []byte {
	w := wire.NewWriter()
	if m.Name != "" {
		w.WriteString(1, m.Name)
	}
	if m.Seats != 0 {
		w.WriteInt32(2, m.Seats)
	}
	return w.Bytes()
}

// UnmarshalProto reads the message out of its bytes.
func (m *SubscriptionPlan) UnmarshalProto(data []byte) error {
	*m = SubscriptionPlan{}
	r := wire.NewReader(data)
	for {
		field, typ, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		switch field {
		case 1:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadString()
			if err != nil {
				return err
			}
			m.Name = value
		case 2:
			if typ != wire.TypeVarint {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadInt32()
			if err != nil {
				return err
			}
			m.Seats = value
		default:
			if err := r.Skip(typ); err != nil {
				return err
			}
		}
	}
	return nil
}

// GetName returns the value of the field.
func (m *SubscriptionPlan) GetName() string {
	if m == nil {
		return ""
	}
	return m.Name
}

// GetSeats returns the value of the field.
func (m *SubscriptionPlan) GetSeats() int32 {
	if m == nil {
		return 0
	}
	return m.Seats
}
