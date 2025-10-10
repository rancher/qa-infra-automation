output "ids" {
  value = [for s in module.elemental_nodes : s.id]
}