resource "datadog_dashboard" "payments" {
  title       = "Oficina Mecânica · Pagamentos"
  description = "Cobranças por status, webhooks do Mercado Pago e chamadas do billing a ele."
  layout_type = "ordered"
  tags        = local.dashboard_tags

  widget {
    note_definition {
      content          = "**As cobranças são criadas e resolvidas?** Janela padrão de 7 dias. Os números vêm do serviço billing, que cria as cobranças no Mercado Pago e recebe as notificações (webhooks) com o resultado."
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
      title       = "Cobranças"

      widget {
        query_value_definition {
          title      = "Cobranças criadas na janela"
          live_span  = "1w"
          autoscale  = false
          precision  = 0
          text_align = "center"

          request {
            q          = "sum:oficina.payment.requested{${local.service_scope["billing"]}}.as_count()"
            aggregator = "sum"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Cobranças resolvidas por status"
          live_span   = "1w"
          show_legend = true

          request {
            display_type = "bars"

            formula {
              formula_expression = "resolvidas"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "resolvidas"
                query       = "sum:oficina.payment.resolved{${local.service_scope["billing"]}} by {oficina.payment.status}.as_count()"
              }
            }
          }
        }
      }

      widget {
        toplist_definition {
          title     = "Cobranças resolvidas por status na janela"
          live_span = "1w"

          request {
            formula {
              formula_expression = "resolvidas"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "resolvidas"
                aggregator  = "sum"
                query       = "sum:oficina.payment.resolved{${local.service_scope["billing"]}} by {oficina.payment.status}.as_count()"
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
      title       = "Webhooks"

      widget {
        timeseries_definition {
          title       = "Webhooks do Mercado Pago recebidos por resultado da assinatura"
          live_span   = "1w"
          show_legend = true

          request {
            display_type = "bars"

            formula {
              formula_expression = "webhooks"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "webhooks"
                query       = "sum:oficina.payment.webhook.received{${local.service_scope["billing"]}} by {outcome}.as_count()"
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
      title       = "Mercado Pago"

      widget {
        timeseries_definition {
          title       = "Duração das chamadas do billing ao Mercado Pago — média e máximo (s)"
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
                query       = "avg:http.client.request.duration{${local.service_scope["billing"]},server.address:api.mercadopago.com}"
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
                query       = "max:http.client.request.duration{${local.service_scope["billing"]},server.address:api.mercadopago.com}"
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
          title       = "Chamadas do billing ao Mercado Pago por status"
          live_span   = "1w"
          show_legend = true

          request {
            display_type = "bars"

            formula {
              formula_expression = "chamadas"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "chamadas"
                query       = "count:http.client.request.duration{${local.service_scope["billing"]},server.address:api.mercadopago.com} by {http.response.status_code}.as_count()"
              }
            }
          }
        }
      }
    }
  }
}
