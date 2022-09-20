variable "permission_sets" {
  description = "A map of permission sets (user roles) with their respective description, list of `managed_policies`, and list of `job_functions`"

  type = map(object({
    description      = string
    managed_policies = list(string)
    job_functions    = list(string)
  }))
}

variable "user_account_roles" {
  description = "A map of target AWS accounts with the list of users and their roles(permission sets) on each account"
  type        = map(map(list(string)))
}

variable "group_account_roles" {
  description = "A map of target AWS accounts with the list of user groups and their roles(permission sets) on each account"
  type        = map(map(list(string)))
}

variable "sso_users" {
  description = "List of SSO user names"
  type        = list(string)
}

variable "sso_groups" {
  description = "List of SSO group names"
  type        = list(string)
}

variable "region" {
  type    = string
  default = "us-east-1"
}
