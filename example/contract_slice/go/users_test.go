package users

import (
	"bytes"
	"testing"
)

func TestTheBytesOfAUser(t *testing.T) {
	user := &User{Id: "u_1", Role: UserRoleAdmin}

	want := []byte{
		0x0a, 0x03, 'u', '_', '1',
		0x20, 0x01,
	}
	if got := user.MarshalProto(); !bytes.Equal(got, want) {
		t.Fatalf("the bytes of the user are %x, want %x", got, want)
	}
}

func TestAUserGoesOnTheWireAndComesBack(t *testing.T) {
	user := &User{
		Id:          "u_1",
		Email:       "user@example.com",
		DisplayName: "The User",
		Role:        UserRoleAdmin,
		Tags:        []string{"one", "two"},
		CreatedAt:   &ProtoTimestamp{Seconds: 1700000000, Nanos: 42},
	}

	other := &User{}
	if err := other.UnmarshalProto(user.MarshalProto()); err != nil {
		t.Fatalf("the user is not read out of its bytes: %v", err)
	}

	if other.Id != user.Id ||
		other.Email != user.Email ||
		other.DisplayName != user.DisplayName ||
		other.Role != user.Role {
		t.Fatalf("the user is %+v, want %+v", other, user)
	}
	if len(other.Tags) != 2 || other.Tags[0] != "one" || other.Tags[1] != "two" {
		t.Fatalf("the tags of the user are %v, want [one two]", other.Tags)
	}
	if other.CreatedAt == nil ||
		other.CreatedAt.Seconds != user.CreatedAt.Seconds ||
		other.CreatedAt.Nanos != user.CreatedAt.Nanos {
		t.Fatalf("the moment of the user is %+v, want %+v", other.CreatedAt, user.CreatedAt)
	}
}

func TestAnEmptyUserGoesOnTheWireAndComesBack(t *testing.T) {
	other := &User{}
	if err := other.UnmarshalProto((&User{}).MarshalProto()); err != nil {
		t.Fatalf("the user is not read out of its bytes: %v", err)
	}
	if other.Id != "" || other.Role != UserRoleUnspecified {
		t.Fatalf("the user is %+v, want an empty user", other)
	}
}

func TestTheBytesOfAListOfUsers(t *testing.T) {
	list := &ListUsersResponse{
		Users:      []*User{{Id: "u_1"}, {Id: "u_2"}},
		NextCursor: "c_1",
	}

	want := []byte{
		0x0a, 0x05, 0x0a, 0x03, 'u', '_', '1',
		0x0a, 0x05, 0x0a, 0x03, 'u', '_', '2',
		0x12, 0x03, 'c', '_', '1',
	}
	if got := list.MarshalProto(); !bytes.Equal(got, want) {
		t.Fatalf("the bytes of the list are %x, want %x", got, want)
	}

	other := &ListUsersResponse{}
	if err := other.UnmarshalProto(want); err != nil {
		t.Fatalf("the list is not read out of its bytes: %v", err)
	}
	if len(other.Users) != 2 || other.Users[0].Id != "u_1" || other.Users[1].Id != "u_2" {
		t.Fatalf("the users of the list are %+v, want two users", other.Users)
	}
	if other.NextCursor != "c_1" {
		t.Fatalf("the cursor of the list is %q, want %q", other.NextCursor, "c_1")
	}
}

func TestTheOneofOfASubscription(t *testing.T) {
	card := "card_1"
	subscription := &Subscription{CardToken: &card}

	other := &Subscription{}
	if err := other.UnmarshalProto(subscription.MarshalProto()); err != nil {
		t.Fatalf("the subscription is not read out of its bytes: %v", err)
	}
	if other.CardToken == nil || *other.CardToken != card {
		t.Fatalf("the card of the subscription is %v, want %q", other.CardToken, card)
	}
	if other.Iban != nil {
		t.Fatalf("the subscription holds the card and the account at once")
	}
}

func TestTheMemberOfAOneofReplacesTheOther(t *testing.T) {
	iban := "iban_1"
	subscription := &Subscription{Iban: &iban}

	other := &Subscription{}
	if err := other.UnmarshalProto(subscription.MarshalProto()); err != nil {
		t.Fatalf("the subscription is not read out of its bytes: %v", err)
	}
	if other.Iban == nil || *other.Iban != iban {
		t.Fatalf("the account of the subscription is %v, want %q", other.Iban, iban)
	}
	if other.CardToken != nil {
		t.Fatalf("the subscription holds the account and the card at once")
	}
}

func TestTheMapOfASubscription(t *testing.T) {
	subscription := &Subscription{
		Features: map[string]bool{"beta": true, "alpha": false},
	}

	other := &Subscription{}
	if err := other.UnmarshalProto(subscription.MarshalProto()); err != nil {
		t.Fatalf("the subscription is not read out of its bytes: %v", err)
	}
	if len(other.Features) != 2 {
		t.Fatalf("the features of the subscription are %v, want two features", other.Features)
	}
	if !other.Features["beta"] || other.Features["alpha"] {
		t.Fatalf("the features of the subscription are %v, want the beta one", other.Features)
	}
}

func TestTheNestedTypesOfASubscription(t *testing.T) {
	subscription := &Subscription{
		Plan:  &SubscriptionPlan{Name: "pro", Seats: 5},
		State: SubscriptionStateActive,
	}

	other := &Subscription{}
	if err := other.UnmarshalProto(subscription.MarshalProto()); err != nil {
		t.Fatalf("the subscription is not read out of its bytes: %v", err)
	}
	if other.Plan == nil || other.Plan.Name != "pro" || other.Plan.Seats != 5 {
		t.Fatalf("the plan of the subscription is %+v, want the pro plan", other.Plan)
	}
	if other.State != SubscriptionStateActive {
		t.Fatalf("the state of the subscription is %v, want it to be active", other.State)
	}
}

func TestTheGettersOfAUser(t *testing.T) {
	var user *User
	if user.GetId() != "" {
		t.Fatalf("the identifier of a user that is not there is %q, want it to be empty", user.GetId())
	}

	user = &User{Id: "u_1"}
	if user.GetId() != "u_1" {
		t.Fatalf("the identifier of the user is %q, want %q", user.GetId(), "u_1")
	}
	if user.GetCreatedAt() != nil {
		t.Fatalf("the moment of the user is %+v, want it to be empty", user.GetCreatedAt())
	}
}

func TestTheNameOfTheValueOfAnEnum(t *testing.T) {
	if UserRoleAdmin.String() != "USER_ROLE_ADMIN" {
		t.Fatalf("the name of the role is %q, want %q", UserRoleAdmin.String(), "USER_ROLE_ADMIN")
	}
	if UserRole(7).String() != "UserRole(7)" {
		t.Fatalf("the name of the role is %q, want %q", UserRole(7).String(), "UserRole(7)")
	}
}
