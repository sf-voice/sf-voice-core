plugins {
    kotlin("jvm") version "2.0.0"
    kotlin("plugin.serialization") version "2.0.0"
    application
}

group = "sh.sfvoice"
version = "0.0.1"

kotlin {
    jvmToolchain(17)
}

application {
    mainClass.set("sh.sfvoice.demo.AppKt")
}

dependencies {
    // local sdk jar — run `gradle jar` from ../../../kotlin first
    implementation(files("../../../kotlin/build/libs/sf-voice-media-0.1.1.jar"))

    // ktor server (embedded netty) + json
    implementation("io.ktor:ktor-server-core:3.0.0")
    implementation("io.ktor:ktor-server-netty:3.0.0")
    implementation("io.ktor:ktor-server-content-negotiation:3.0.0")
    implementation("io.ktor:ktor-serialization-kotlinx-json:3.0.0")

    // sdk runtime deps
    implementation("io.ktor:ktor-client-core:3.0.0")
    implementation("io.ktor:ktor-client-cio:3.0.0")
    implementation("io.ktor:ktor-client-content-negotiation:3.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
}
