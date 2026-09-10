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
    defaults = [var.api_service]
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

      # Sem `rollup` fixo. Um `rollup(sum, 86400)` produz um balde diario que so
      # fecha a meia-noite: em qualquer janela que nao termine ali, o ultimo
      # balde aparece parcial e o destino o rotula `interval in progress`.
      # Deixando o destino escolher o intervalo, a largura da barra acompanha a
      # janela selecionada e nao existe balde aberto.
      widget {
        timeseries_definition {
          title     = "Ordens de serviço criadas"
          live_span = "1w"

          request {
            q            = "sum:oficina.work_order.created{$env,$service}.as_count()"
            display_type = "bars"
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
            q            = "avg:oficina.work_order.status.duration{$env,$service} by {oficina.work_order.status}"
            display_type = "line"
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
              alias              = "máximo"
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

      # O funil sai da METRICA, nao do log. `oficina.work_order.status.duration`
      # e emitida quando a ordem SAI de um status, entao `count:` dela por
      # status responde quantas ordens avancaram de cada etapa -- que e a
      # pergunta que o funil faz.
      #
      # O evento de log `work_order.status.updated` nao serve para isso: ele so
      # e emitido em duas das seis transicoes (`RECEIVED -> IN_DIAGNOSIS` e
      # `COMPLETED -> DELIVERED`). As demais sao efeito de acoes de dominio e
      # emitem os seus proprios eventos.
      widget {
        toplist_definition {
          title     = "Ordens que saíram de cada status na janela"
          live_span = "1w"

          request {
            q = "count:oficina.work_order.status.duration{$env,$service} by {oficina.work_order.status}.as_count()"
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
          title     = "Decisões de orçamento — aprovados contra recusados"
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
                  query = "service:$service env:$env @oficina.event.name:(quote.approved OR quote.rejected)"
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
