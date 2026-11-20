// The frontend of the workspace.
//
// The build of the frontend belongs to the application: put the result of it
// in the directory of the files.

async function main() {
  // The app calls the services behind it, so the frontend talks to the app
  // and not to the services. The token of the session of the browser travels
  // with the call.
  const token = sessionStorage.getItem("token") ?? "";
  const shopGateway = await fetch(
    "/v1/shop_gateway/u_1",
    { headers: { authorization: token } },
  );
  return Promise.all([
    shopGateway.then((response) => response.json()),
  ]);
}

main().catch((error) => console.error(error));
