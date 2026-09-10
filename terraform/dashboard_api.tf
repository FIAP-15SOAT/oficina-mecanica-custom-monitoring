resource "datadog_dashboard" "api" {
  title       = "Oficina Mecânica · API"
  description = "Performance e erros da API. Detalhe do grupo API da Visão Geral."
  layout_type = "ordered"
  tags        = local.dashboard_tags

  template_variable {
    name     = "env"
    prefix   = "env"
    defaults = [var.env]
  }

  template_variable {
    name     = "service"
    prefix   = "service"
    defaults = [var.api_service]
  }

  widget {
    note_definition {
      content          = "**Onde a API está lenta, e por quê?** Janela padrão de 1 hora. Os grupos seguem o caminho da requisição: entrada, dependência, processo, evidência.\n\nLatência vem de `http.server.request.duration` (OTLP, em **segundos**), não das métricas de trace do APM — o nome da operação delas muda com a versão do agente.\n\nAs dimensões indexadas desta métrica são **apenas** `env`, `service`, `http.route` e `http.response.status_code` — quebrar por método HTTP ou por versão não é possível aqui, porque são dimensões descartadas do índice para conter o custo de custom metrics."
      background_color = "blue"
      font_size        = "14"
      text_align       = "left"
      vertical_align   = "top"
      has_padding      = true
    }
  }

  widget {
    group_definition {
      layout_type = "ordered"
      title       = "Requisições"

      widget {
        timeseries_definition {
          title       = "Requisições por classe de status (req/min)"
          live_span   = "1h"
          show_legend = true

          request {
            display_type = "bars"

            formula {
              formula_expression = "ok"
              alias              = "2xx"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "ok"
                query       = "count:http.server.request.duration{$env,$service,http.response.status_code:2*}.as_count().rollup(sum, 60)"
              }
            }
          }

          request {
            display_type = "bars"

            formula {
              formula_expression = "client_error"
              alias              = "4xx"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "client_error"
                query       = "count:http.server.request.duration{$env,$service,http.response.status_code:4*}.as_count().rollup(sum, 60)"
              }
            }
          }

          request {
            display_type = "bars"

            formula {
              formula_expression = "server_error"
              alias              = "5xx"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "server_error"
                query       = "count:http.server.request.duration{$env,$service,http.response.status_code:5*}.as_count().rollup(sum, 60)"
              }
            }
          }
        }
      }

      # `top()` ordena e corta; quem reduz a série ao número exibido é o
      # agregador do widget, cujo padrão é MÉDIA. Num widget que promete
      # "requisições na janela", média por intervalo é a leitura errada.
      widget {
        toplist_definition {
          title     = "Top 10 rotas por volume (requisições na janela)"
          live_span = "1h"

          request {
            formula {
              formula_expression = "volume"

              limit {
                count = 10
                order = "desc"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "volume"
                aggregator  = "sum"
                query       = "count:http.server.request.duration{$env,$service} by {http.route}.as_count()"
              }
            }
          }
        }
      }
      widget {
        query_table_definition {
          title     = "Rotas · volume, p50 (s), p95 (s) e % de 5xx"
          live_span = "1h"

          request {
            formula {
              formula_expression = "volume"
              alias              = "requisições"
              limit {
                count = 20
                order = "desc"
              }
            }

            formula {
              formula_expression = "p50"
              alias              = "p50 (s)"
            }

            formula {
              formula_expression = "p95"
              alias              = "p95 (s)"
            }

            formula {
              formula_expression = "errors / volume * 100"
              alias              = "% de 5xx"

              conditional_formats {
                comparator = ">"
                value      = 5
                palette    = "white_on_red"
              }

              conditional_formats {
                comparator = ">"
                value      = 1
                palette    = "white_on_yellow"
              }

              conditional_formats {
                comparator = "<="
                value      = 1
                palette    = "white_on_green"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "volume"
                query       = "count:http.server.request.duration{$env,$service} by {http.route}.as_count()"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "p50"
                query       = "p50:http.server.request.duration{$env,$service} by {http.route}"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "p95"
                query       = "p95:http.server.request.duration{$env,$service} by {http.route}"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "errors"
                query       = "count:http.server.request.duration{$env,$service,http.response.status_code:5*} by {http.route}.as_count()"
              }
            }
          }
        }
      }
    }
  }

  widget {
    group_definition {
      layout_type = "ordered"
      title       = "Latência"

      widget {
        timeseries_definition {
          title       = "Latência p50, p90, p95 e p99 (s)"
          live_span   = "1h"
          show_legend = true

          request {
            display_type = "line"

            formula {
              formula_expression = "p50"
              alias              = "p50"
            }

            formula {
              formula_expression = "p90"
              alias              = "p90"
            }

            formula {
              formula_expression = "p95"
              alias              = "p95"
            }

            formula {
              formula_expression = "p99"
              alias              = "p99"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "p50"
                query       = "p50:http.server.request.duration{$env,$service}"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "p90"
                query       = "p90:http.server.request.duration{$env,$service}"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "p95"
                query       = "p95:http.server.request.duration{$env,$service}"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "p99"
                query       = "p99:http.server.request.duration{$env,$service}"
              }
            }
          }

          # Os dois limiares do monitor de latência, desenhados: quem olha o
          # gráfico vê onde o alerta dispara sem abrir a definição do monitor.
          marker {
            display_type = "warning dashed"
            label        = "warning latência p95 (${var.api_latency_p95_warning_seconds}s)"
            value        = "y = ${var.api_latency_p95_warning_seconds}"
          }

          marker {
            display_type = "error dashed"
            label        = "critical latência p95 (${var.api_latency_p95_critical_seconds}s)"
            value        = "y = ${var.api_latency_p95_critical_seconds}"
          }
        }
      }

      widget {
        distribution_definition {
          title     = "Distribuição de latência na janela (s)"
          live_span = "1h"

          request {
            q = "avg:http.server.request.duration{$env,$service}"
          }
        }
      }

      widget {
        toplist_definition {
          title     = "Top 10 rotas por p95 (s)"
          live_span = "1h"

          request {
            q = "top(p95:http.server.request.duration{$env,$service} by {http.route}, 10, 'mean', 'desc')"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      layout_type = "ordered"
      title       = "Banco"

      widget {
        note_definition {
          content          = "Percentis desta métrica exigiriam habilitá-los explicitamente, o que multiplicaria o custo de custom metrics sem que nenhum monitor dependa deles. Este grupo usa **média e máximo**, que são gratuitos."
          background_color = "yellow"
          font_size        = "12"
          text_align       = "left"
          vertical_align   = "top"
          has_padding      = true
        }
      }

      widget {
        timeseries_definition {
          title       = "Duração de operação no banco por operação — média e máximo (s)"
          live_span   = "1h"
          show_legend = true

          request {
            display_type = "line"

            formula {
              formula_expression = "media"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "media"
                query       = "avg:db.client.operation.duration{$env,$service} by {db.operation.name}"
              }
            }
          }

          request {
            display_type = "line"

            formula {
              formula_expression = "maximo"
              alias              = "máximo geral"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "maximo"
                query       = "max:db.client.operation.duration{$env,$service}"
              }
            }

            style {
              palette   = "warm"
              line_type = "dashed"
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Pool de conexões — usadas e ociosas contra o máximo"
          live_span   = "1h"
          show_legend = true

          request {
            display_type = "area"

            formula {
              formula_expression = "conexoes"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "conexoes"
                query       = "avg:db.client.connection.count{$env,$service} by {db.client.connection.state}"
              }
            }
          }

          request {
            display_type = "line"

            formula {
              formula_expression = "maximo"
              alias              = "máximo do pool"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "maximo"
                query       = "avg:db.client.connection.max{$env,$service}"
              }
            }

            style {
              palette   = "warm"
              line_type = "dashed"
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title     = "Requisições aguardando conexão no pool"
          live_span = "1h"

          request {
            display_type = "bars"

            formula {
              formula_expression = "aguardando"
              alias              = "aguardando conexão"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "aguardando"
                query       = "avg:db.client.connection.pending_requests{$env,$service}"
              }
            }
          }
        }
      }
    }
  }

  widget {
    group_definition {
      layout_type = "ordered"
      title       = "Runtime"

      widget {
        timeseries_definition {
          title     = "Atraso do event loop, p99 (s)"
          live_span = "1h"

          request {
            display_type = "line"

            formula {
              formula_expression = "atraso"
              alias              = "atraso p99"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "atraso"
                query       = "avg:nodejs.eventloop.delay.p99{$env,$service}"
              }
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title     = "Utilização do event loop (0 a 1)"
          live_span = "1h"

          request {
            display_type = "line"

            formula {
              formula_expression = "utilizacao"
              alias              = "utilização"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "utilizacao"
                query       = "avg:nodejs.eventloop.utilization{$env,$service}"
              }
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Heap V8 — usado contra alocado (bytes)"
          live_span   = "1h"
          show_legend = true

          request {
            display_type = "area"

            formula {
              formula_expression = "usado"
              alias              = "usado"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "usado"
                query       = "avg:v8js.memory.heap.used{$env,$service}"
              }
            }
          }

          request {
            display_type = "line"

            formula {
              formula_expression = "alocado"
              alias              = "alocado"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "alocado"
                query       = "sum:v8js.memory.heap.space.size{$env,$service}"
              }
            }

            style {
              palette   = "warm"
              line_type = "dashed"
            }
          }
        }
      }
    }
  }

  widget {
    group_definition {
      layout_type = "ordered"
      title       = "Erros"

      widget {
        log_stream_definition {
          title     = "Logs de erro da API"
          live_span = "1h"
          query     = "service:$service env:$env status:error"

          columns = [
            "core_service",
            "@http.route",
            "@http.response.status_code",
            "@error.type",
            "@oficina.error.message",
          ]

          message_display     = "expanded-md"
          show_date_column    = true
          show_message_column = true

          sort {
            column = "time"
            order  = "desc"
          }
        }
      }
    }
  }
}
