# Install or upgrade a release
#
# @param release          Installation name (what is this deployment called?)
# @param chart            Chart name, or your name for this deployment and set `chart_url`
# @param chart_url        Chart name if it doesn't match `name`, or a full `oci://` URL
# @param hooks            Enable or disable install hooks
# @param namespace        Kubernetes namespace to manage
# @param remove_resources A list of keys to remove from the resources map (i.e. don't deploy these!)
# @param render_to        Just save the fully-rendered chart to this yaml file
# @param repo_name        Optional name of the Helm repo to add
# @param repo_url         Optional URL of the Helm repo to add
# @param version          Optional Helm chart version
# @param wait             Wait for resources to become available
# @param subcharts        Additional charts to deploy as part of this one
# @param parent           Private. The parent release this one is being rendered for.
# @param build_dir        Scratch directory for compiling manifests
plan kubecm::deploy (
  String           $release,
  String           $chart            = $release,
  String           $chart_url        = $chart,
  Boolean          $hooks            = true,
  Optional[String] $namespace        = undef,
  Array[String]    $remove_resources = [],
  Optional[String] $render_to        = undef,
  Optional[String] $repo_name        = undef,
  Optional[String] $repo_url         = undef,
  Optional[String] $version          = undef,
  Boolean          $wait             = false,
  Array[Hash]      $subcharts        = [],
  Optional[String] $parent           = undef,

  # Project settings
  # (set your own defaults in Hiera)
  String $build_dir     = lookup('kubecm::deploy::build_dir'),
  String $resources_key = lookup('kubecm::deploy::resources_key'),
  String $values_key    = lookup('kubecm::deploy::values_key'),
  String $patches_key   = lookup('kubecm::deploy::patches_key'),
) {
  $subchart_manifests = $subcharts.map |$subchart| {
    $manifest = "${subchart['release']}.yaml"
    run_plan('kubecm::deploy', $subchart + {
      parent    => $release,
      namespace => $namespace,
      render_to => "${build_dir}/${manifest}",
    })
    $manifest
  }

  if $repo_name and $repo_url {
    $chart_url_real = "${repo_name}/${chart_url}"
    $helm_repo_add_cmd = "helm repo add ${repo_name} ${repo_url}"
    run_command($helm_repo_add_cmd, 'localhost', "Add Helm repo ${repo_name} at ${repo_url}")
  } else {
    $chart_url_real = $chart_url
  }

  # Because YAML plans
  if $render_to and $render_to != '' {
    $render_to_real = $render_to
  } else {
    $render_to_real = undef
  }

  # Figure out where we are
  $readlink_cmd  = "readlink -f ${build_dir.shellquote}"
  $abs_build_dir = run_command($readlink_cmd, 'localhost', 'Determine absolute path to build dir').first.value['stdout'].chomp

  apply('localhost') {
    $kubecm_release        = $release
    $kubecm_chart          = $chart
    $kubecm_namespace      = $namespace
    $kubecm_parent_release = $parent

    include kubecm::deploy # defines variables needed for lookups

    $resources = lookup($resources_key, Hash, 'hash', {}) - $remove_resources
    $values    = lookup($values_key, Hash, 'deep', {})
    $patches   = lookup($patches_key, Hash, 'hash', {})

    file {
      $abs_build_dir:
        ensure => directory,
      ;

      "${abs_build_dir}/resources.yaml":
        content => $resources.values.flatten.map |$r| { if $r.empty { '' } else { $r.stdlib::to_yaml } }.join,
      ;

      "${abs_build_dir}/values.yaml":
        content => $values.stdlib::to_yaml,
      ;

      "${abs_build_dir}/kustomization.yaml":
        content => {
          'resources' => $subchart_manifests + ['resources.yaml', 'helm.yaml'],
          'patches'   => $patches.keys.sort.map |$k| { $patches[$k] }.flatten.map |$p| {
            if $p['patch'] =~ String {
              $p
            } else {
              $p + { 'patch' => $p['patch'].stdlib::to_yaml }
            }
          },
        }.stdlib::to_yaml,
      ;

      "${abs_build_dir}/kustomize.sh":
        mode   => '0755',
        source => 'puppet:///modules/kubecm/kustomize.sh',
      ;
    }
  }

  $helm_cmd = [
    'helm',

    $render_to_real ? {
      undef   => ['upgrade', '--install'],
      default => 'template',
    },

    $release, $chart_url_real,

    $hooks ? {
      false   => '--no-hooks',
      default => [],
    },

    $namespace ? {
      undef   => [],
      default => ['--create-namespace', '--namespace', $namespace],
    },

    '--post-renderer', "${build_dir}/kustomize.sh",
    '--post-renderer-args', $build_dir,
    '--values', "${build_dir}/values.yaml",

    $version ? {
      undef   => [],
      default => ['--version', $version],
    },

    ($wait and !$render_to_real) ? {
      true    => ['--wait', '--timeout', '1h'],
      default => [],
    },
  ].flatten.shellquote

  if $render_to_real {
    $redirect = " > ${render_to_real.shellquote}"
    $cmd_verb = 'Render'
  } else {
    $redirect = ''
    $cmd_verb = 'Deploy'
  }

  return run_command("${helm_cmd}${redirect}", 'localhost', "${cmd_verb} ${release} from Helm chart ${chart_url_real}")
}
