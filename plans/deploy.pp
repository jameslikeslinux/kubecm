# Install or upgrade a release
#
# @param release          Installation name (what is this deployment called)
# @param chart            Chart name, or your name for this deployment and set `chart_source`
# @param chart_source     Typically `repo_name/chart_name` or an `oci://` URI, but could be a local path,
#                           a valid Puppet file source, or `undef` for no chart (just Hiera resources).
# @param hooks            Enable or disable install hooks
# @param namespace        Kubernetes namespace to manage
# @param remove_resources A list of keys to remove from the resources map (i.e. don't deploy these!)
# @param render_to        Just save the fully-rendered chart to this yaml file
# @param repo_url         Optional URL of the Helm repo to add
# @param version          Optional Helm chart version
# @param wait             Wait for resources to become available
# @param subcharts        Additional charts to deploy as part of this one
# @param parent           Private. The parent release this one is being rendered for.
# @param build_dir        Scratch directory for compiling manifests
plan kubecm::deploy (
  String           $release,
  String           $chart            = $release,
  Optional[String] $chart_source     = undef,
  Boolean          $hooks            = true,
  Optional[String] $namespace        = undef,
  Array[String]    $remove_resources = [],
  Optional[String] $render_to        = undef,
  Optional[String] $repo_url         = undef,
  Optional[String] $version          = undef,
  Boolean          $wait             = false,
  Array[Hash]      $subcharts        = [],
  Optional[String] $parent           = undef,
  String           $build_dir        = lookup('kubecm::deploy::build_dir'),
) {
  $subchart_manifests = $subcharts.map |$subchart| {
    $manifest = "${subchart['release']}.yaml"
    run_plan('kubecm::deploy', $subchart + {
        parent    => $release,
        namespace => $namespace,
        render_to => "${build_dir}/${manifest}",
      }
    )
    $manifest
  }

  if $build_dir =~ Stdlib::Absolutepath {
    $build_dir_real = $build_dir
  } else {
    $pwd = run_command('pwd', 'localhost', 'Determine current working directory').first.value['stdout'].chomp
    $build_dir_real = file::join($pwd, $build_dir)
  }

  # Build Kustomize config
  apply('localhost') {
    class { 'kubecm::deploy':
      build_dir          => $build_dir_real,
      chart_source       => $chart_source,
      remove_resources   => $remove_resources,
      subchart_manifests => $subchart_manifests,
    }
  }.kubecm::print_report

  if !$chart_source or $chart_source =~ Stdlib::Filesource {
    $chart_source_real = "${build_dir_real}/chart"
  } elsif $chart_source =~ /^(\w+)\// and $repo_url {
    $chart_source_real = $chart_source
    $repo_name = $1
    $helm_repo_add_cmd = "helm repo add ${repo_name.shellquote} ${repo_url.shellquote}"
    run_command($helm_repo_add_cmd, 'localhost', "Add Helm repo ${repo_name} at ${repo_url}")
  } elsif $chart_source =~ /^oci:/ {
    $chart_source_real = $chart_source
  } else {
    $chart_source_real = file::join('.', $chart_source)
  }

  $helm_cmd = [
    'helm',

    $render_to ? {
      undef   => ['upgrade', '--install'],
      default => 'template',
    },

    $release, $chart_source_real,

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

    ($wait and !$render_to) ? {
      true    => ['--wait', '--timeout', '1h'],
      default => [],
    },
  ].flatten.shellquote

  if $render_to {
    $redirect = " > ${render_to.shellquote}"
    $cmd_verb = 'Render'
  } else {
    $redirect = ''
    $cmd_verb = 'Deploy'
  }

  $result = run_command("${helm_cmd}${redirect}", 'localhost', "${cmd_verb} ${release} from Helm chart ${chart_source_real}").first

  return $result
}
