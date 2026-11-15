resource "datadog_dashboard" "sagas" {
  title       = "Oficina Mecânica · Sagas"
  description = "Sagas iniciadas e finalizadas, duração e compensações por motivo."
  layout_type = "ordered"
  tags        = local.dashboard_tags

  widget {
    note_definition {
      content          = "**As transações distribuídas terminam?** Janela padrão de 7 dias.\n\nDetalhe: [Ordens de Serviço — funil por status](${local.dashboard_url_work_orders}) · [Mensageria — as mensagens estão fluindo?](${local.dashboard_url_messaging}) · [Runbook — mensagem na DLQ](${local.runbook_url}#mensagem-na-dlq)"
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
      title       = "Iniciadas e finalizadas"

      widget {
        timeseries_definition {
          title       = "Sagas iniciadas por tipo"
          live_span   = "1w"
          show_legend = true

          request {
            display_type = "bars"

            formula {
              formula_expression = "iniciadas"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "iniciadas"
                query       = "sum:oficina.saga.started{${local.service_scope["work-order"]}} by {oficina.saga.type}.as_count()"
              }
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Sagas finalizadas por tipo e resultado"
          live_span   = "1w"
          show_legend = true

          request {
            display_type = "bars"

            formula {
              formula_expression = "finalizadas"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "finalizadas"
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
      title       = "Sem finalização e compensação"

      # Same reducer rule as the work-order funnel: a table cell reduces the
      # per-interval count to one number, and the default reducer is the mean.
      widget {
        query_table_definition {
          title     = "Sagas por tipo · iniciadas sem finalização e % compensadas na janela"
          live_span = "1w"

          request {
            formula {
              formula_expression = "iniciadas - finalizadas"
              alias              = "iniciadas sem finalização"
            }

            formula {
              formula_expression = "compensadas / finalizadas * 100"
              alias              = "% compensadas"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "iniciadas"
                aggregator  = "sum"
                query       = "sum:oficina.saga.started{${local.service_scope["work-order"]}} by {oficina.saga.type}.as_count()"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "finalizadas"
                aggregator  = "sum"
                query       = "sum:oficina.saga.finished{${local.service_scope["work-order"]}} by {oficina.saga.type}.as_count()"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "compensadas"
                aggregator  = "sum"
                query       = "sum:oficina.saga.finished{${local.service_scope["work-order"]},oficina.saga.outcome:compensated} by {oficina.saga.type}.as_count()"
              }
            }
          }
        }
      }

      widget {
        note_definition {
          content          = "Diferença positiva em `QUOTE_APPROVAL`, que termina em segundos, é Saga parada: abrir [Mensageria](${local.dashboard_url_messaging}) e o [runbook de DLQ](${local.runbook_url}#mensagem-na-dlq). A Saga `PAYMENT` fica aberta enquanto a cobrança aguarda o pagamento do cliente, até expirar; diferença nela só é parada se a cobrança já foi resolvida no dashboard de [Pagamentos](${local.dashboard_url_payments})."
          background_color = "yellow"
          font_size        = "12"
          text_align       = "left"
          vertical_align   = "top"
          has_padding      = true
        }
      }
    }
  }

  widget {
    group_definition {
      layout_type = "ordered"
      title       = "Duração"

      widget {
        timeseries_definition {
          title       = "Duração das Sagas por tipo — média e máximo (s)"
          live_span   = "1w"
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
                query       = "avg:oficina.saga.duration{${local.service_scope["work-order"]}} by {oficina.saga.type}"
              }
            }
          }

          request {
            display_type = "line"

            formula {
              formula_expression = "maximo"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "maximo"
                query       = "max:oficina.saga.duration{${local.service_scope["work-order"]}} by {oficina.saga.type}"
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
      title       = "Compensações por motivo"

      widget {
        toplist_definition {
          title     = "Sagas compensadas por tipo e motivo na janela"
          live_span = "1w"

          request {
            formula {
              formula_expression = "compensacoes"
            }

            query {
              event_query {
                data_source = "logs"
                name        = "compensacoes"
                indexes     = ["*"]

                compute {
                  aggregation = "count"
                }

                search {
                  query = "${local.service_log_scope["work-order"]} @oficina.event.name:saga.compensated"
                }

                group_by {
                  facet = "@oficina.saga.type"
                  limit = 5

                  sort {
                    aggregation = "count"
                    order       = "desc"
                  }
                }

                group_by {
                  facet = "@oficina.saga.failure_reason"
                  limit = 10

                  sort {
                    aggregation = "count"
                    order       = "desc"
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
