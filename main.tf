provider "aws" {
  region = var.region
}

locals {
  sso_users          = var.sso_users
  user_account_roles = var.user_account_roles

  sso_groups          = var.sso_groups
  group_account_roles = var.group_account_roles

  permission_sets = var.permission_sets

  sso_instance_arn      = tolist(data.aws_ssoadmin_instances.sso.arns)[0]
  sso_identity_store_id = tolist(data.aws_ssoadmin_instances.sso.identity_store_ids)[0]

  managed_policies = merge(flatten([
    for k, v in local.permission_sets : [
      for policy_arn in v.managed_policies : {
        "${k}_${split("/", policy_arn)[1]}" = {
          permission_set = "${k}"
          policy_arn     = policy_arn
        }
      }
    ]
  ])...)

  job_functions = merge(flatten([
    for k, v in local.permission_sets : [
      for policy_arn in v.job_functions : {
        "${k}_${split("/", policy_arn)[1]}" = {
          permission_set = k
          policy_arn     = policy_arn
        }
      }
    ]
  ])...)

  inline_policy_file_path = "${path.module}/templates/{PERMSET}-inline-policy.tmpl.json"

  inline_policy_files = { for k, v in local.permission_sets : k =>
    {
      permission_set = k
      policy_content = file(replace(local.inline_policy_file_path, "{PERMSET}", lower(k)))
    } if fileexists(replace(local.inline_policy_file_path, "{PERMSET}", lower(k)))
  }

  inline_policies = { for k, v in local.inline_policy_files : k => v if v.policy_content != "" }

  sso_user_roles = merge(flatten([
    for account_id, users in local.user_account_roles : [
      for user, roles in users : [
        for role in roles : {
          "${account_id}_${user}_${role}" = {
            account_id = account_id
            user       = user
            role       = role
          }
        }
      ]
    ]
  ])...)

  sso_group_roles = merge(flatten([
    for account_id, groups in local.group_account_roles : [
      for group, roles in groups : [
        for role in roles : {
          "${account_id}_${group}_${role}" = {
            account_id = account_id
            group      = group
            role       = role
          }
        }
      ]
    ]
  ])...)
}

data "aws_ssoadmin_instances" "sso" {}

data "aws_identitystore_user" "sso_user" {
  for_each          = toset(local.sso_users)
  identity_store_id = local.sso_identity_store_id

  filter {
    attribute_path  = "UserName"
    attribute_value = each.key
  }
}

data "aws_identitystore_group" "sso_group" {
  for_each          = toset(local.sso_groups)
  identity_store_id = local.sso_identity_store_id

  filter {
    attribute_path  = "DisplayName"
    attribute_value = each.key
  }
}

resource "aws_ssoadmin_permission_set" "permissions" {
  for_each         = local.permission_sets
  name             = each.key
  description      = each.value.description
  instance_arn     = local.sso_instance_arn
  session_duration = "PT12H"

  tags = {
    "Name" = each.key
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "managed_policies" {
  for_each           = local.managed_policies
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = each.value.policy_arn
  permission_set_arn = aws_ssoadmin_permission_set.permissions[each.value.permission_set].arn
  depends_on = [
    aws_ssoadmin_permission_set.permissions
  ]
}

resource "aws_ssoadmin_managed_policy_attachment" "job_functions" {
  for_each           = local.job_functions
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = each.value.policy_arn
  permission_set_arn = aws_ssoadmin_permission_set.permissions[each.value.permission_set].arn
  depends_on = [
    aws_ssoadmin_permission_set.permissions
  ]
}

resource "aws_ssoadmin_permission_set_inline_policy" "inline_policies" {
  for_each           = local.inline_policies
  inline_policy      = each.value.policy_content
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.permissions[each.value.permission_set].arn
  depends_on = [
    aws_ssoadmin_permission_set.permissions
  ]
}

resource "aws_ssoadmin_account_assignment" "user_permissions" {
  for_each           = local.sso_user_roles
  instance_arn       = aws_ssoadmin_permission_set.permissions[each.value.role].instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.permissions[each.value.role].arn

  principal_id   = data.aws_identitystore_user.sso_user[each.value.user].user_id
  principal_type = "USER"

  target_id   = each.value.account_id
  target_type = "AWS_ACCOUNT"
  depends_on = [
    aws_ssoadmin_permission_set.permissions
  ]
}

resource "aws_ssoadmin_account_assignment" "group_permissions" {
  for_each           = local.sso_group_roles
  instance_arn       = aws_ssoadmin_permission_set.permissions[each.value.role].instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.permissions[each.value.role].arn

  principal_id   = data.aws_identitystore_group.sso_group[each.value.group].group_id
  principal_type = "GROUP"

  target_id   = each.value.account_id
  target_type = "AWS_ACCOUNT"
  depends_on = [
    aws_ssoadmin_permission_set.permissions
  ]
}
