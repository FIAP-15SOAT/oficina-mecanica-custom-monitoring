resource "datadog_dashboard" "overview" {
  title       = "Oficina Mecânica · Visão Geral"
  description = "A solução está de pé agora? Ponto de entrada dos quatro dashboards."
  layout_type = "ordered"
  tags        = local.dashboard_tags

  widget {
    note_definition {
      content          = "**A solução está de pé agora?** Janela padrão de 4 horas.\n\nDetalhe: [API — onde está lenta e por quê](${local.dashboard_url_api}) · [Ordens de Serviço — o fluxo está andando?](${local.dashboard_url_work_orders}) · [Kubernetes — os pods têm folga?](${local.dashboard_url_kubernetes})\n\nO laboratório é ligado sob demanda e destruído ao fim de cada sessão. Com o ambiente fora, todo número desta página é zero ou vazio, e **isso é o estado esperado, não incidente** — nenhum monitor notifica por ausência de dado."
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
      title       = "Disponibilidade"

      widget {
        alert_graph_definition {
          title     = "Verificação externa da rota pública — histórico"
          alert_id  = datadog_synthetics_test.api_health.monitor_id
          viz_type  = "timeseries"
          live_span = "4h"
        }
      }

      widget {
        manage_status_definition {
          title               = "Monitores da solução"
          query               = "tag:(project:${var.project_name})"
          summary_type        = "monitors"
          sort                = "status,asc"
          display_format      = "countsAndList"
          color_preference    = "text"
          hide_zero_counts    = true
          show_last_triggered = true
          show_priority       = true
        }
      }
    }
  }

  widget {
    group_definition {
      layout_type = "ordered"
      title       = "API"

      widget {
        query_value_definition {
          title      = "Requisições por minuto"
          live_span  = "4h"
          autoscale  = true
          precision  = 1
          text_align = "center"

          request {
            q          = "count:http.server.request.duration{${local.api_scope}}.as_count().rollup(sum, 60)"
            aggregator = "avg"
          }
        }
      }

      widget {
        query_value_definition {
          title       = "Respostas 5xx (% do total)"
          live_span   = "4h"
          autoscale   = false
          precision   = 2
          custom_unit = "%"
          text_align  = "center"

          request {
            formula {
              formula_expression = "(erros / total) * 100"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "erros"
                aggregator  = "sum"
                query       = "count:http.server.request.duration{${local.api_scope},http.response.status_code:5*}.as_count()"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "total"
                aggregator  = "sum"
                query       = "count:http.server.request.duration{${local.api_scope}}.as_count()"
              }
            }

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
        }
      }

      widget {
        query_value_definition {
          title       = "Latência p95 (s)"
          live_span   = "4h"
          autoscale   = false
          precision   = 3
          custom_unit = "s"
          text_align  = "center"

          request {
            q          = "p95:http.server.request.duration{${local.api_scope}}"
            aggregator = "avg"

            conditional_formats {
              comparator = ">"
              value      = var.api_latency_p95_critical_seconds
              palette    = "white_on_red"
            }

            conditional_formats {
              comparator = ">"
              value      = var.api_latency_p95_warning_seconds
              palette    = "white_on_yellow"
            }

            conditional_formats {
              comparator = "<="
              value      = var.api_latency_p95_warning_seconds
              palette    = "white_on_green"
            }
          }
        }
      }
    }
  }

  widget {
    group_definition {
      layout_type = "ordered"
      title       = "Negócio"

      widget {
        query_value_definition {
          title      = "Ordens de serviço criadas hoje"
          live_span  = "1d"
          autoscale  = false
          precision  = 0
          text_align = "center"

          request {
            q          = "sum:oficina.work_order.created{${local.api_scope}}.as_count()"
            aggregator = "sum"
          }
        }
      }

      widget {
        toplist_definition {
          title     = "Permanência média por status (s)"
          live_span = "1d"

          request {
            q = "avg:oficina.work_order.status.duration{${local.api_scope}} by {oficina.work_order.status}"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      layout_type = "ordered"
      title       = "Infra"

      widget {
        query_value_definition {
          title      = "Pods da API emitindo métrica"
          live_span  = "4h"
          autoscale  = false
          precision  = 0
          text_align = "center"

          request {
            q          = "count_nonzero(avg:kubernetes.memory.working_set{${local.k8s_scope}} by {pod_name})"
            aggregator = "last"

            conditional_formats {
              comparator = "<"
              value      = 1
              palette    = "white_on_red"
            }

            conditional_formats {
              comparator = ">="
              value      = 1
              palette    = "white_on_green"
            }
          }
        }
      }

      widget {
        toplist_definition {
          title     = "Memória sobre o limite por pod (%)"
          live_span = "4h"

          request {
            formula {
              formula_expression = "(uso / limite) * 100"

              conditional_formats {
                comparator = ">"
                value      = var.pod_memory_critical_percent
                palette    = "white_on_red"
              }

              conditional_formats {
                comparator = ">"
                value      = var.pod_memory_warning_percent
                palette    = "white_on_yellow"
              }

              conditional_formats {
                comparator = "<="
                value      = var.pod_memory_warning_percent
                palette    = "white_on_green"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "uso"
                query       = "avg:kubernetes.memory.working_set{${local.k8s_scope}} by {pod_name}"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "limite"
                query       = "avg:kubernetes.memory.limits{${local.k8s_scope}} by {pod_name}"
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
      title       = "Lambda customer-auth"

      widget {
        query_value_definition {
          title      = "Invocações na janela"
          live_span  = "4h"
          autoscale  = false
          precision  = 0
          text_align = "center"

          request {
            q          = "sum:aws.lambda.enhanced.invocations{${local.lambda_scope}}.as_count()"
            aggregator = "sum"
          }
        }
      }

      widget {
        query_value_definition {
          title      = "Erros de plataforma na janela"
          live_span  = "4h"
          autoscale  = false
          precision  = 0
          text_align = "center"

          request {
            q          = "sum:aws.lambda.enhanced.errors{${local.lambda_scope}}.as_count()"
            aggregator = "sum"

            conditional_formats {
              comparator = ">"
              value      = 0
              palette    = "white_on_red"
            }

            conditional_formats {
              comparator = "<="
              value      = 0
              palette    = "white_on_green"
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Duração — média e máximo (s)"
          live_span   = "4h"
          show_legend = true

          request {
            q            = "avg:aws.lambda.enhanced.duration{${local.lambda_scope}}"
            display_type = "line"
          }

          request {
            q            = "max:aws.lambda.enhanced.duration{${local.lambda_scope}}"
            display_type = "line"

            style {
              palette   = "warm"
              line_type = "dashed"
            }
          }
        }
      }

      widget {
        query_value_definition {
          title       = "Partidas a frio (% das invocações)"
          live_span   = "4h"
          autoscale   = false
          precision   = 1
          custom_unit = "%"
          text_align  = "center"

          request {
            formula {
              formula_expression = "(frias / total) * 100"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "frias"
                aggregator  = "sum"
                query       = "sum:aws.lambda.enhanced.invocations{${local.lambda_scope},cold_start:true}.as_count()"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "total"
                aggregator  = "sum"
                query       = "sum:aws.lambda.enhanced.invocations{${local.lambda_scope}}.as_count()"
              }
            }
          }
        }
      }
    }
  }
}
