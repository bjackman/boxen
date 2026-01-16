{
  mkPromQuery =
    { query, seriesNameFormat }:
    {
      kind = "TimeSeriesQuery";
      spec.plugin = {
        kind = "PrometheusTimeSeriesQuery";
        spec = {
          datasource = {
            kind = "PrometheusDatasource";
            name = "prometheus";
          };
          inherit query seriesNameFormat;
        };
      };
    };
  mkTSPanel =
    {
      name,
      description,
      queries,
      unit ? null,
      shortValues ? false,
      fromZero ? false,
    }:
    {
      kind = "Panel";
      spec = {
        display = { inherit name description; };
        plugin = {
          kind = "TimeSeriesChart";
          spec = {
            legend = {
              mode = "table";
              position = "bottom";
              values = [ "last" ];
            };
          }
          // (
            if unit != null then
              {
                yAxis = {
                  format = {
                    inherit unit;
                  }
                  // (if shortValues then { inherit shortValues; } else { });
                }
                // (if fromZero then { min = 0; } else { });
              }
            else
              { }
          );
        };
        inherit queries;
      };
    };
  mkGrid =
    { title, panels }:
    {
      kind = "Grid";
      spec = {
        display.title = title;
        items = map (p: {
          x = p.x;
          y = 0;
          width = 12;
          height = 8;
          content."$ref" = "#/spec/panels/${p.ref}";
        }) panels;
      };
    };
}
