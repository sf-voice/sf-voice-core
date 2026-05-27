plugins {
    java
    id("org.springframework.boot") version "3.3.0"
    id("io.spring.dependency-management") version "1.1.5"
}

group = "com.sfvoice"
version = "0.0.1"

java {
    sourceCompatibility = JavaVersion.VERSION_17
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    // local sdk jar — run `gradle jar` from ../../../java first
    implementation(files("../../../java/build/libs/sf-voice-media-0.1.0.jar"))
    // jackson is provided by spring-boot-starter-web; jackson-databind pulled in by the sdk
    implementation("com.fasterxml.jackson.core:jackson-databind:2.17.1")
}
