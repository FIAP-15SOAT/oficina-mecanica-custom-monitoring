resource "datadog_dashboard" "messaging" {
  title       = "Oficina Mecânica · Mensageria"
  description = "Consumo das filas SQS por resultado, DLQ por tipo de mensagem e falhas de publicação do outbox."
  layout_type = "ordered"
  tags        = local.dashboard_tags

  # Linking back to Sagas would make Terraform report a dependency cycle,
  # since the Sagas dashboard already links here.
  widget {
    note_definition {
      content          = "**As mensagens estão fluindo?** Janela padrão de 4 horas.\n\nProfundidade de fila e idade da mensagem mais antiga são métricas do SQS que exigem a integração AWS do Datadog, bloqueada no laboratório. No lugar delas, os gráficos abaixo usam o que as aplicações registram: cada mensagem consumida com o resultado (sucesso, nova tentativa ou DLQ, a fila para onde vai a mensagem depois de 5 tentativas), o evento de mensagem enviada à DLQ e as falhas do outbox (a tabela de onde cada serviço publica as mensagens no tópico SNS). O identity não consome fila.\n\nMensagem na DLQ: [runbook](${local.runbook_url}#mensagem-na-dlq)"
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
      title       = "Consumo"

      widget {
        timeseries_definition {
          title       = "Mensagens consumidas por fila e resultado"
          live_span   = "4h"
          show_legend = true

          request {
            display_type = "bars"

            formula {
              formula_expression = "consumidas"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "consumidas"
                query       = "sum:oficina.messaging.consumed{${local.services_scope}} by {messaging.destination.name,outcome}.as_count()"
              }
            }
          }
        }
      }

      widget {
        toplist_definition {
          title     = "Mensagens consumidas por fila e resultado na janela"
          live_span = "4h"

          request {
            formula {
              formula_expression = "consumidas"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "consumidas"
                aggregator  = "sum"
                query       = "sum:oficina.messaging.consumed{${local.services_scope}} by {messaging.destination.name,outcome}.as_count()"
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
      title       = "Fila da Lambda notification"

      widget {
        timeseries_definition {
          title       = "E-mails da fila notification.fifo por resultado"
          live_span   = "4h"
          show_legend = true

          request {
            display_type = "bars"

            formula {
              formula_expression = "emails"
            }

            query {
              event_query {
                data_source = "logs"
                name        = "emails"
                indexes     = ["*"]

                compute {
                  aggregation = "count"
                }

                search {
                  query = "service:${local.lambdas["notification"].service} env:${var.env} @oficina.event.name:(notification.sent OR notification.failed)"
                }

                group_by {
                  facet = "@oficina.notification.outcome"
                  limit = 5

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

  widget {
    group_definition {
      layout_type = "ordered"
      title       = "DLQ"

      widget {
        toplist_definition {
          title     = "Mensagens enviadas à DLQ por serviço, fila e tipo na janela"
          live_span = "4h"

          request {
            formula {
              formula_expression = "dlq"
            }

            query {
              event_query {
                data_source = "logs"
                name        = "dlq"
                indexes     = ["*"]

                compute {
                  aggregation = "count"
                }

                search {
                  query = "${local.services_scope} @oficina.event.name:messaging.message.dead_lettered"
                }

                group_by {
                  facet = "service"
                  limit = 5

                  sort {
                    aggregation = "count"
                    order       = "desc"
                  }
                }

                group_by {
                  facet = "@messaging.destination.name"
                  limit = 10

                  sort {
                    aggregation = "count"
                    order       = "desc"
                  }
                }

                group_by {
                  facet = "@oficina.messaging.message.type"
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

  widget {
    group_definition {
      layout_type = "ordered"
      title       = "Outbox"

      widget {
        timeseries_definition {
          title       = "Falhas de publicação do outbox por serviço"
          live_span   = "4h"
          show_legend = true

          request {
            display_type = "bars"

            formula {
              formula_expression = "falhas"
            }

            query {
              event_query {
                data_source = "logs"
                name        = "falhas"
                indexes     = ["*"]

                compute {
                  aggregation = "count"
                }

                search {
                  query = "${local.services_scope} @oficina.event.name:messaging.outbox.publish_failed"
                }

                group_by {
                  facet = "service"
                  limit = 5

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
