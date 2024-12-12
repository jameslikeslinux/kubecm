# Puppet entrypoint for the kubecm::deploy plan
#
# This defines the following variables for use in your Hiera hierarchy
# and data, and declares other classes for your own custom variables.
#
#   * kubecm::deploy::release
#   * kubecm::deploy::chart
#   * kubecm::deploy::namespace
#   * kubecm::deploy::parent_release
#
# @param classes_key Hiera key mapping a list of custom classes to declare
# @api private
class kubecm::deploy (
  String $classes_key,
) {
  # lint:ignore:top_scope_facts
  $release   = pick_default($::release)
  $chart     = pick_default($::chart)
  $namespace = pick_default($::namespace, 'default')
  $parent    = pick_default($::parent)
  # lint:endignore

  hiera_include($classes_key)
}
