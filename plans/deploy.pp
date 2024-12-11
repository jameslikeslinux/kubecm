# Install or upgrade a release
#
# @param release   Installation name (what is this deployment called?)
# @param name      What kind of thing is being deployed (probably the chart name, but maybe not)
# @param chart     Chart name (if it doesn't match `name`) or a full `oci://` URL
# @param hooks     Enable or disable install hooks
# @param namespace Kubernetes namespace to manage
# @param render_to Just save the fully-rendered chart to this yaml file
# @param repo_name Optional name of the Helm repo to add
# @param repo_url  Optional URL of the Helm repo to add
# @param version   Optional Helm chart version
# @param wait      Wait for resources to become available
# @param subcharts Additional charts to deploy as part of this one
# @param parent    Private. The parent release this one is being rendered for.
plan kubecm::deploy (
  String           $release,
  String           $name      = $release,
  String           $chart     = $name,
  Boolean          $hooks     = true,
  Optional[String] $namespace = undef,
  Optional[String] $render_to = undef,
  Optional[String] $repo_name = undef,
  Optional[String] $repo_url  = undef,
  Optional[String] $version   = undef,
  Boolean          $wait      = false,
  Array[Hash]      $subcharts = [],
  Optional[String] $parent    = undef,
  String           $builddir  = lookup("${module_name}::deploy::builddir"),
) {
  $subcharts.map |$subchart| {
    run_plan('nest::kubernetes::deploy', $subchart + {
      parent    => $release,
      namespace => $namespace,
      render_to => '/tmp/kustomize/subcharts.yaml',
    })
  }
}
