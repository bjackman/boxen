// Shows gerrit-ci's runs in the change screen's Checks tab. The runner already
// serves them in the Checks API's shape; this only fetches them.
Gerrit.install((plugin) => {
  const ciUrl = "@ciUrl@";

  plugin.checks().register(
    {
      async fetch(change) {
        if (change.repo !== "@project@") {
          return { responseCode: "OK", runs: [] };
        }
        let response;
        try {
          // The runner is behind the IAP, which needs the session cookie.
          response = await fetch(`${ciUrl}/api/checks/${change.changeNumber}`, {
            credentials: "include",
          });
        } catch (e) {
          // An expired IAP session redirects to the login page, which fails
          // CORS and is indistinguishable from the runner being down.
          return {
            responseCode: "ERROR",
            errorMessage: `Couldn't reach ${ciUrl}: the CI runner is down, or the login there has expired.`,
          };
        }
        if (!response.ok) {
          return {
            responseCode: "ERROR",
            errorMessage: `${ciUrl} said ${response.status}: ${await response.text()}`,
          };
        }
        const { runs } = await response.json();
        for (const run of runs) {
          for (const key of ["startedTimestamp", "finishedTimestamp"]) {
            if (run[key]) run[key] = new Date(run[key]);
          }
        }
        return { responseCode: "OK", runs };
      },
    },
    { fetchPollingIntervalSeconds: 30 },
  );
});
