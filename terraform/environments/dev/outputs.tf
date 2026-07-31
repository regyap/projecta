output "foundation" {
  value = {
    vpc_id               = module.foundation.vpc_id
    public_subnet_ids    = module.foundation.public_subnet_ids
    private_subnet_ids   = module.foundation.private_subnet_ids
    artifact_bucket      = module.foundation.artifact_bucket
    event_table          = module.foundation.event_table
    deployment_queue_url = module.foundation.deployment_queue_url
    deployment_dlq_url   = module.foundation.deployment_dlq_url
    event_bus_name       = module.foundation.event_bus_name
    webhook_url          = module.foundation.webhook_url
  }
}

