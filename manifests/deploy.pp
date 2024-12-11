# Puppet entrypoint for the kubecm::deploy plan
#
# This defines the following variables for use in your Hiera hiearchy
# and data, and declares other classes for your own custom variables.
#
#   * kubecm::deploy::release
#   * kubecm::deploy::chart
#   * kubecm::deploy::namespace
#   * kubecm::deploy::parent_release
#
# @param classes Include other classes that define variables for lookups
class kubecm::deploy (
  Array[String] $classes = [],
) {
  # lint:ignore:top_scope_facts
  $release        = pick_default($::kubecm_release)
  $chart          = pick_default($::kubecm_chart)
  $namespace      = pick_default($::kubecm_namespace, 'default')
  $parent_release = pick_default($::kubecm_parent_release)
  # lint:endignore

  include $classes
}
