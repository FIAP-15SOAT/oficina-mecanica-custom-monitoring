locals {
  # No comma in this scope: the destination rejects `,` mixed with `OR`.
  overview_k8s_scope = join(" OR ", [for k in keys(local.services) : "kube_namespace:${k}"])

  overview_service_links = join(" · ", [for k in keys(local.services) : "[${k}](${local.dashboard_url_service[k]})"])
}

resource "datadog_dashboard" "overview" {
  title       = "Oficina Mecânica · Visão Geral"
  description = "Disponibilidade, volume, erros e latência de cada serviço, indicadores de negócio, pods e Lambdas. Ponto de entrada dos dashboards de detalhe."
  layout_type = "ordered"
  tags        = local.dashboard_tags

  widget {
    note_definition {
      content          = "**A solução está de pé agora?** Janela padrão de 4 horas.\n\nServiços — onde está lento e por quê: ${local.overview_service_links}\n\nDetalhe: [Ordens de Serviço — o fluxo está andando?](${local.dashboard_url_work_orders}) · [Sagas — as transações distribuídas terminam?](${local.dashboard_url_sagas}) · [Pagamentos — as cobranças são criadas e resolvidas?](${local.dashboard_url_payments}) · [Mensageria — as mensagens estão fluindo?](${local.dashboard_url_messaging}) · [Kubernetes — os pods têm folga?](${local.dashboard_url_kubernetes})\n\nO laboratório é ligado sob demanda e destruído ao fim de cada sessão. Com o ambiente fora, todo número desta página é zero ou vazio, e **isso é o estado esperado, não incidente** — nenhum monitor notifica por ausência de dado."
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

  dynamic "widget" {
    for_each = local.services

    content {
      group_definition {
        layout_type = "ordered"
        title       = "Serviço ${widget.key}"

        widget {
          alert_graph_definition {
            title     = "Verificação externa de /health/${widget.key} — histórico"
            alert_id  = datadog_synthetics_test.service_health[widget.key].monitor_id
            viz_type  = "timeseries"
            live_span = "4h"
          }
        }

        widget {
          manage_status_definition {
            title            = "Monitores do serviço"
            query            = "tag:(service:${widget.value.service})"
            summary_type     = "monitors"
            sort             = "status,asc"
            display_format   = "counts"
            color_preference = "text"
            hide_zero_counts = true
          }
        }

        widget {
          query_value_definition {
            title      = "Requisições por minuto"
            live_span  = "4h"
            autoscale  = true
            precision  = 1
            text_align = "center"

            request {
              q          = "count:http.server.request.duration{${local.service_scope[widget.key]}}.as_count().rollup(sum, 60)"
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
                  query       = "count:http.server.request.duration{${local.service_scope[widget.key]},http.response.status_code:5*}.as_count()"
                }
              }

              query {
                metric_query {
                  data_source = "metrics"
                  name        = "total"
                  aggregator  = "sum"
                  query       = "count:http.server.request.duration{${local.service_scope[widget.key]}}.as_count()"
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
              q          = "p95:http.server.request.duration{${local.service_scope[widget.key]}}"
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
            q          = "sum:oficina.work_order.created{${local.service_scope["work-order"]}}.as_count()"
            aggregator = "sum"
          }
        }
      }

      widget {
        toplist_definition {
          title     = "Permanência média por status (s)"
          live_span = "1d"

          request {
            formula {
              formula_expression = "permanencia"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "permanencia"
                query       = "avg:oficina.work_order.status.duration{${local.service_scope["work-order"]}} by {oficina.work_order.status}"
              }
            }
          }
        }
      }

      widget {
        toplist_definition {
          title     = "Sagas finalizadas hoje por tipo e desfecho"
          live_span = "1d"

          request {
            formula {
              formula_expression = "finalizadas"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "finalizadas"
                aggregator  = "sum"
                query       = "sum:oficina.saga.finished{${local.service_scope["work-order"]}} by {oficina.saga.type,oficina.saga.outcome}.as_count()"
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
      title       = "Infra"

      widget {
        query_value_definition {
          title      = "Pods dos serviços emitindo métrica"
          live_span  = "4h"
          autoscale  = false
          precision  = 0
          text_align = "center"

          request {
            q          = "count_nonzero(avg:kubernetes.memory.working_set{${local.overview_k8s_scope}} by {kube_namespace,pod_name})"
            aggregator = "last"

            # Each service runs at least one pod, so fewer pods than services means one is down.
            conditional_formats {
              comparator = "<"
              value      = length(local.services)
              palette    = "white_on_red"
            }

            conditional_formats {
              comparator = ">="
              value      = length(local.services)
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
                query       = "avg:kubernetes.memory.working_set{${local.overview_k8s_scope}} by {kube_namespace,pod_name}"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "limite"
                query       = "avg:kubernetes.memory.limits{${local.overview_k8s_scope}} by {kube_namespace,pod_name}"
              }
            }
          }
        }
      }
    }
  }

  dynamic "widget" {
    for_each = local.lambdas

    content {
      group_definition {
        layout_type = "ordered"
        title       = "Lambda ${widget.key}"

        widget {
          query_value_definition {
            title      = "Invocações na janela"
            live_span  = "4h"
            autoscale  = false
            precision  = 0
            text_align = "center"

            request {
              q          = "sum:aws.lambda.enhanced.invocations{${local.lambda_scope[widget.key]}}.as_count()"
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
              q          = "sum:aws.lambda.enhanced.errors{${local.lambda_scope[widget.key]}}.as_count()"
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
              display_type = "line"

              formula {
                formula_expression = "media"
                alias              = "média"
              }

              query {
                metric_query {
                  data_source = "metrics"
                  name        = "media"
                  query       = "avg:aws.lambda.enhanced.duration{${local.lambda_scope[widget.key]}}"
                }
              }
            }

            request {
              display_type = "line"

              formula {
                formula_expression = "maximo"
                alias              = "máximo"
              }

              query {
                metric_query {
                  data_source = "metrics"
                  name        = "maximo"
                  query       = "max:aws.lambda.enhanced.duration{${local.lambda_scope[widget.key]}}"
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
                  query       = "sum:aws.lambda.enhanced.invocations{${local.lambda_scope[widget.key]},cold_start:true}.as_count()"
                }
              }

              query {
                metric_query {
                  data_source = "metrics"
                  name        = "total"
                  aggregator  = "sum"
                  query       = "sum:aws.lambda.enhanced.invocations{${local.lambda_scope[widget.key]}}.as_count()"
                }
              }
            }
          }
        }
      }
    }
  }
}
