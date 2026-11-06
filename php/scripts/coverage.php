<?php
// Fails when the line coverage in a Clover report is under a floor: php scripts/coverage.php build/clover.xml 85
declare(strict_types=1);

[$script, $report, $floor] = $argv + [null, null, '85'];
if ($report === null || !is_file($report)) {
    fwrite(STDERR, "usage: php $script <clover.xml> [floor]\n");
    exit(2);
}
$xml = simplexml_load_file($report);
if ($xml === false || !isset($xml->project->metrics)) {
    fwrite(STDERR, "$report is not a Clover report.\n");
    exit(2);
}
$metrics = $xml->project->metrics;
$statements = (int) $metrics['statements'];
$covered = (int) $metrics['coveredstatements'];
$percent = $statements === 0 ? 0.0 : $covered / $statements * 100;
printf("Line coverage: %.1f%% (%d of %d statements); the floor is %s%%.\n", $percent, $covered, $statements, $floor);
exit($percent + 1e-9 >= (float) $floor ? 0 : 1);
