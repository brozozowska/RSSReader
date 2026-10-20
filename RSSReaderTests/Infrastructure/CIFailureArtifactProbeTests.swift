import Testing

@Suite("CI / Temporary Failure Artifact Probe")
struct CIFailureArtifactProbeTests {
    @Test
    func intentionalFailureProducesDownloadableXCResult() {
        Issue.record("Intentional #722 failure-artifact verification; removed after CI evidence readback")
    }
}
