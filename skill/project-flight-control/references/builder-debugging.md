# Builder failure-only debugging protocol

Load this reference only after a test, build, or observed behavior failure. For one failure path: read error fully; reproduce it; inspect current Revision/diff and the affected call path; form one hypothesis; make the smallest test of that hypothesis; apply one root-cause fix; then rerun affected verification.

Count code, test, or configuration changes made for the same symptom or root-cause path. Allow at most two code-changing attempts. Repeating an unchanged command to confirm intermittence, correcting an invalid command or path, restoring the environment, formatting without behavior change, and the first verification after environment recovery do not consume an attempt. A separately evidenced new failure starts its own path; relabeling the same failure does not.

If the second code-changing attempt does not converge, return a BUILD_REPORT with status FAIL or PARTIAL together with DEBUGGING_SUMMARY containing the symptom, evidence, hypotheses, attempts, remaining risk, and recommended handoff, then stop. Do not apply stacked speculative patches, delete tests, weaken assertions, or continue by relabeling the same failure as a new issue.
