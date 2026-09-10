resource "datadog_dashboard" "kubernetes" {
  title       = "Oficina Mecânica · Kubernetes"
  description = "Recursos dos pods da API, medidos pelo kubelet."
  layout_type = "ordered"
  tags        = local.api_tags

  widget {
    note_definition {
      content          = "**Os pods da API estão com folga de recurso, ou vão ser encerrados?** Janela padrão de 4 horas.\n\n**Não há Cluster Agent nesta instalação.** A coleta de recursos do cluster está desligada (`Live Pods → No Results Found`), então `kubernetes_state.*` não existe: não há réplicas desejadas contra disponíveis, `pod.ready`, condição de nó nem estado de HPA. O widget de réplicas abaixo conta pods que **emitem métrica**, que é uma aproximação de \"pods vivos\", não de \"pods prontos\".\n\nPara a visão de plataforma que este dashboard não cobre, o destino já traz um dashboard pronto: **Kubernetes** (`Dashboards → Kubernetes`), alimentado pela mesma coleta do kubelet.\n\nMemória é `working_set`, e não `usage`, porque `working_set` é o que o encerramento por falta de memória observa. CPU de uso vem em **nanocores** e é dividida por 1e9 para comparar com `requests` e `limits`, que vêm em cores."
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
      title       = "CPU"

      widget {
        timeseries_definition {
          title       = "CPU por pod contra requests e limits (cores)"
          live_span   = "4h"
          show_legend = true

          request {
            display_type = "area"

            formula {
              formula_expression = "uso / 1000000000"
              alias              = "uso"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "uso"
                query       = "avg:kubernetes.cpu.usage.total{${local.k8s_scope}} by {pod_name}"
              }
            }
          }

          request {
            display_type = "line"

            formula {
              formula_expression = "requests"
              alias              = "requests"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "requests"
                query       = "avg:kubernetes.cpu.requests{${local.k8s_scope}} by {pod_name}"
              }
            }

            style {
              line_type = "dashed"
            }
          }

          request {
            display_type = "line"

            formula {
              formula_expression = "limits"
              alias              = "limits"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "limits"
                query       = "avg:kubernetes.cpu.limits{${local.k8s_scope}} by {pod_name}"
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
          title     = "Estrangulamento de CPU por pod (% dos períodos)"
          live_span = "4h"

          request {
            display_type = "bars"

            formula {
              formula_expression = "(estrangulados / periodos) * 100"
              alias              = "% estrangulado"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "estrangulados"
                query       = "sum:kubernetes.cpu.cfs.throttled.periods{${local.k8s_scope}} by {pod_name}"
              }
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "periodos"
                query       = "sum:kubernetes.cpu.cfs.periods{${local.k8s_scope}} by {pod_name}"
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
      title       = "Memória"

      widget {
        timeseries_definition {
          title       = "Working set por pod contra o limite (bytes)"
          live_span   = "4h"
          show_legend = true

          request {
            q            = "avg:kubernetes.memory.working_set{${local.k8s_scope}} by {pod_name}"
            display_type = "area"
          }

          request {
            q            = "avg:kubernetes.memory.limits{${local.k8s_scope}} by {pod_name}"
            display_type = "line"

            style {
              palette   = "warm"
              line_type = "dashed"
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title     = "Working set sobre o limite por pod (%)"
          live_span = "4h"

          request {
            display_type = "line"

            formula {
              formula_expression = "(uso / limite) * 100"
              alias              = "% do limite"
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

          marker {
            display_type = "warning dashed"
            label        = "warning M5 (${var.pod_memory_warning_percent}%)"
            value        = "y = ${var.pod_memory_warning_percent}"
          }

          marker {
            display_type = "error dashed"
            label        = "critical M5 (${var.pod_memory_critical_percent}%)"
            value        = "y = ${var.pod_memory_critical_percent}"
          }
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Ciclo de vida
  # ---------------------------------------------------------------------------
  widget {
    group_definition {
      layout_type = "ordered"
      title       = "Ciclo de vida"

      # `kubernetes.containers.running` não carrega `pod_name` (responde `N/A`),
      # então a contagem sai de `count_nonzero` sobre uma métrica que carrega.
      # Isso conta pods que emitem métrica, não pods prontos.
      widget {
        query_value_definition {
          title      = "Pods emitindo métrica"
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
        timeseries_definition {
          title     = "Reinícios de contêiner por pod"
          live_span = "4h"

          request {
            q            = "max:kubernetes.containers.restarts{${local.k8s_scope}} by {pod_name}"
            display_type = "bars"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      layout_type = "ordered"
      title       = "Nós do cluster"
      widget {
        timeseries_definition {
          title     = "CPU em uso por nó (%)"
          live_span = "4h"

          request {
            display_type = "line"

            formula {
              formula_expression = "100 - ocioso"
              alias              = "% em uso"
            }

            query {
              metric_query {
                data_source = "metrics"
                name        = "ocioso"
                query       = "avg:system.cpu.idle{kube_cluster_name:${var.kube_cluster_name}} by {host}"
              }
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title     = "Memória utilizável por nó (%)"
          live_span = "4h"

          request {
            q            = "avg:system.mem.pct_usable{kube_cluster_name:${var.kube_cluster_name}} by {host}"
            display_type = "line"
          }
        }
      }
    }
  }
}
