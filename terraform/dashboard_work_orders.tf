resource "datadog_dashboard" "work_orders" {
  title       = "Oficina Mecânica · Ordens de Serviço"
  description = "Fluxo de negócio: volume, permanência por status, lead time e transições."
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
    defaults = [local.services["work-order"].service]
  }

  widget {
    note_definition {
      content          = "**O fluxo de ordens de serviço está andando, e onde ele para?** Janela padrão de 7 dias."
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
      title       = "Volume"

      # Unambiguous window total. The last bar of the chart beside it is always
      # partial (the current interval is still filling) and the destination
      # labels it `interval in progress`; this value has no such problem.
      widget {
        query_value_definition {
          title      = "Ordens de serviço criadas na janela"
          live_span  = "1w"
          autoscale  = false
          precision  = 0
          text_align = "center"

          request {
            q          = "sum:oficina.work_order.created{$env,$service}.as_count()"
            aggregator = "sum"
          }
        }
      }

      # No fixed `rollup`. A `rollup(sum, 86400)` pins the bucket to a whole day,
      # which closes only at midnight: in any window ending elsewhere, the current
      # bucket shows a partial total as if it were the day's. Letting the
      # destination pick the interval makes the bar width follow the window.
      widget {
        timeseries_definition {
          title     = "Ordens de serviço criadas ao longo da janela"
          live_span = "1w"

          request {
            display_type = "bars"

            formula {
              formula_expression = "criadas"
              alias              = "ordens criadas"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "criadas"
                query       = "sum:oficina.work_order.created{$env,$service}.as_count()"
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
      title       = "Permanência por status"

      widget {
        timeseries_definition {
          title       = "Permanência média por status (s)"
          live_span   = "1w"
          show_legend = true

          request {
            display_type = "line"

            formula {
              formula_expression = "permanencia"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "permanencia"
                query       = "avg:oficina.work_order.status.duration{$env,$service} by {oficina.work_order.status}"
              }
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Permanência máxima por status (s)"
          live_span   = "1w"
          show_legend = true

          request {
            display_type = "line"

            formula {
              formula_expression = "maximo"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "maximo"
                query       = "max:oficina.work_order.status.duration{$env,$service} by {oficina.work_order.status}"
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
      title       = "Ciclo completo"

      widget {
        timeseries_definition {
          title       = "Lead time — média e máximo (s)"
          live_span   = "1w"
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
                query       = "avg:oficina.work_order.lead_time.duration{$env,$service}"
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
                query       = "max:oficina.work_order.lead_time.duration{$env,$service}"
              }
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Diagnóstico até conclusão — média e máximo (s)"
          live_span   = "1w"
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
                query       = "avg:oficina.work_order.diagnosis_to_completion.duration{$env,$service}"
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
                query       = "max:oficina.work_order.diagnosis_to_completion.duration{$env,$service}"
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
      title       = "Funil e decisões"

      # The funnel comes from the METRIC, not the log. `oficina.work_order.status.duration`
      # is emitted when the order LEAVES a status, so its `count:` by status
      # answers how many orders moved past each step.
      #
      # The log event `work_order.status.updated` does not fit: it is emitted on
      # only two of the six transitions (`RECEIVED -> IN_DIAGNOSIS` and
      # `COMPLETED -> DELIVERED`). The others are side effects of domain actions
      # and emit their own events.
      #
      # `aggregator = "sum"` is required: a toplist reduces the series to one
      # number, and the default reduction is the MEAN, which over a per-interval
      # count gives values like `1.5 orders`. The short `q = "..."` form cannot
      # pick the reducer; the formula form can.
      widget {
        toplist_definition {
          title     = "Ordens que saíram de cada status na janela"
          live_span = "1w"

          request {
            formula {
              formula_expression = "saidas"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "saidas"
                aggregator  = "sum"
                query       = "count:oficina.work_order.status.duration{$env,$service} by {oficina.work_order.status}.as_count()"
              }
            }
          }
        }
      }

      widget {
        note_definition {
          content          = "Os status terminais **não aparecem** aqui: `DELIVERED` e `CANCELLED` não emitem permanência, porque não se sai deles. O número de cada etapa é quantas ordens **avançaram** dela na janela."
          background_color = "yellow"
          font_size        = "12"
          text_align       = "left"
          vertical_align   = "top"
          has_padding      = true
        }
      }

      widget {
        toplist_definition {
          title     = "Decisões de orçamento no billing — aprovados contra recusados"
          live_span = "1w"

          request {
            formula {
              formula_expression = "decisoes"
            }

            query {
              event_query {
                data_source = "logs"
                name        = "decisoes"
                indexes     = ["*"]

                compute {
                  aggregation = "count"
                }

                search {
                  query = "service:${local.services["billing"].service} env:$env @oficina.event.name:(quote.approved OR quote.rejected)"
                }

                group_by {
                  facet = "@oficina.event.name"
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
