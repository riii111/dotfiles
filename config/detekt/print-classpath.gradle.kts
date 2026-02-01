// Gradle init script to print compile classpath as JAR file paths
// Usage: ./gradlew :module:printClasspath -I /path/to/this/file -q

allprojects {
    tasks.register("printClasspath") {
        doLast {
            configurations.findByName("compileClasspath")?.files?.forEach {
                println(it.absolutePath)
            }
        }
    }
}
