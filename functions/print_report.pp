function kubecm::print_report(ResultSet $apply_results) {
  $apply_results.each |$result| {
    $result.report['logs'].each |$log| {
      out::message("${log['level'].capitalize}: ${log['source']}: ${log['message']}")
    }
  }
}
