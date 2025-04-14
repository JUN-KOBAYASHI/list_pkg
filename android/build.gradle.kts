// android/build.gradle.kts (完全版 - configure構文修正版)

// ===== import文 (ファイルの先頭に追加・確認) =====
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element
// LibraryExtension を使うので import
import com.android.build.gradle.LibraryExtension

// ===== allprojects ブロック (既存) =====
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// ===== buildDirectory 設定 (既存) =====
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

// ===== 修正された subprojects ブロック (configure構文修正) =====
subprojects {
    // 既存の buildDirectory 設定
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // 既存の evaluationDependsOn 設定
    project.evaluationDependsOn(":app")

    // --- Namespace 自動設定コード (構文修正版) ---
    // Android ライブラリプラグインが適用された時のみ処理
    pluginManager.withPlugin("com.android.library") {
        // android (LibraryExtension) の設定ブロックを取得して設定
        try { // extensions.configure が失敗するケースも考慮
            extensions.configure<LibraryExtension> { // <- 引数なしのラムダに変更
                // namespace が null の場合のみ処理
                if (namespace == null) { // <- libraryExtension. を削除
                    // AndroidManifest.xml ファイルのパスを取得 (標準的なパス)
                    val manifestFile = project.file("src/main/AndroidManifest.xml")

                    fun getPackageNameFromManifest(manifestPath: File): String? {
                        try {
                            if (!manifestPath.exists()) return null
                            val dbFactory = DocumentBuilderFactory.newInstance()
                            val dBuilder = dbFactory.newDocumentBuilder()
                            val doc = dBuilder.parse(manifestPath)
                            val rootElement = doc.documentElement
                            // package属性を取得し、空でない場合のみ返す
                            return rootElement.getAttribute("package").takeIf { it.isNotEmpty() }
                        } catch (e: Exception) {
                            println(">> WARN: Failed to parse ${manifestPath.name} for ${project.name}: ${e.message}")
                            return null
                        }
                    }

                    var packageName: String? = getPackageNameFromManifest(manifestFile)

                    // 標準パスで見つからない場合、代替パスを試す
                    if (packageName == null) {
                        try {
                            // libraryExtension. を削除して sourceSets に直接アクセス
                            val alternativeManifestFile = sourceSets.getByName("main").manifest.srcFile
                            packageName = getPackageNameFromManifest(alternativeManifestFile)
                        } catch (e: Exception) {
                            println(">> WARN: Could not get alternative manifest path for ${project.name}: ${e.message}")
                        }
                    }

                    // パッケージ名が取得できたら namespace に設定
                    if (packageName != null) {
                        println(">> Setting namespace for ${project.name} to ${packageName} (auto-detected)")
                        namespace = packageName // <- libraryExtension. を削除
                    } else {
                        // namespace を自動設定できなかった場合、警告を出す
                        println(">> WARN: Could not auto-detect package attribute in AndroidManifest.xml for ${project.name}. Namespace not set.")
                    }
                }
            }
        } catch (e: Exception) {
            println(">> WARN: Failed to configure LibraryExtension for ${project.name}: ${e.message}")
        }
    }
    // --- 追加ここまで ---
}


// ===== clean タスク (既存) =====
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}