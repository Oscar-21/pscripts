package graph.apponlyperm;

import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import java.util.concurrent.atomic.AtomicInteger;
import com.azure.core.credential.AccessToken;
import com.azure.core.credential.TokenRequestContext;
import com.azure.identity.ClientSecretCredential;
import com.azure.identity.ClientSecretCredentialBuilder;
import com.microsoft.aad.msal4j.TokenCache;
import com.microsoft.graph.models.MailFolder;
import com.microsoft.graph.models.MailFolderCollectionResponse;
import com.microsoft.graph.models.Message;
import com.microsoft.graph.models.MessageCollectionResponse;
import com.microsoft.graph.models.UserCollectionResponse;
import com.microsoft.graph.serviceclient.GraphServiceClient;

import com.azure.core.credential.AccessToken;
import com.azure.core.credential.TokenRequestContext;


public class Graph {
   private static final String SHARED_INBOX_USER_ID = "bf633496-da9f-48de-a73a-25f2da8a25fe";
//  private static final String SHARED_INBOX_USER_ID = "2232e813-911a-4916-bdac-ebaeeb7fda32";
  private static Properties _properties;
  private static ClientSecretCredential _clientSecretCredential;
  private static GraphServiceClient _appClient;

  public static void initializeGraphForAppOnlyAuth(Properties properties) throws Exception {
    // Ensure properties isn't null


    TokenRequestContext ctx =
        new TokenRequestContext().addScopes("https://graph.microsoft.com/.default");

    if (properties == null) {
      throw new Exception("Properties cannot be null");
    }

    _properties = properties;

    if (_clientSecretCredential == null) {
      final String clientId = _properties.getProperty("app.clientId");
      final String tenantId = _properties.getProperty("app.tenantId");
      final String clientSecret = _properties.getProperty("app.clientSecret");

      _clientSecretCredential = new ClientSecretCredentialBuilder().clientId(clientId)
          .tenantId(tenantId).clientSecret(clientSecret).build();


      AccessToken token = _clientSecretCredential.getToken(ctx).block();
      if (token != null) {
        System.out.println("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        System.out.println(token.getToken());
        System.out.println("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
      } else {
        System.out.println("??????????????????????????????????????????????????????????????");
        System.out.println("No Token");
        System.out.println("??????????????????????????????????????????????????????????????");
      }
    }

    if (_appClient == null) {
      _appClient = new GraphServiceClient(_clientSecretCredential,
          new String[] {"https://graph.microsoft.com/.default"});
    }
  }

  public static String getAppOnlyToken() throws Exception {
    // Ensure credential isn't null
    if (_clientSecretCredential == null) {
      throw new Exception("Graph has not been initialized for app-only auth");
    }

    // Request the .default scope as required by app-only auth
    final String[] graphScopes = new String[] {"https://graph.microsoft.com/.default"};

    final TokenRequestContext context = new TokenRequestContext();
    context.addScopes(graphScopes);

    final AccessToken token = _clientSecretCredential.getToken(context).block();
    return token.getToken();
  }

  public static UserCollectionResponse getUsers() throws Exception {
    // Ensure client isn't null
    if (_appClient == null) {
      throw new Exception("Graph has not been initialized for app-only auth");
    }

    return _appClient.users().get(requestConfig -> {
      requestConfig.queryParameters.select = new String[] {"displayName", "id", "mail"};
      requestConfig.queryParameters.top = 25;
      requestConfig.queryParameters.orderby = new String[] {"displayName"};
    });
  }

  public static List<MailFolder> getMailFolders() throws Exception {
    // Ensure client isn't null
    if (_appClient == null) {
      throw new Exception("Graph has not been initialized for user auth");
    }
    List<MailFolder> mailFolders = new ArrayList<>();
    final int top = 10;
    AtomicInteger skip = new AtomicInteger(0);
    while (true) {
      MailFolderCollectionResponse page =
          _appClient.users().byUserId(SHARED_INBOX_USER_ID).mailFolders().get(requestConfig -> {
            requestConfig.queryParameters.top = top;
            requestConfig.queryParameters.skip = skip.get();
            requestConfig.queryParameters.count = true;
            requestConfig.queryParameters.select = new String[] {"id", "displayName"};
          });
      if (page == null || page.getValue() == null || page.getValue().isEmpty()) {
        break;
      } else {
        mailFolders.addAll(page.getValue());
        skip.addAndGet(top);
      }
    }
    return mailFolders;
  }

  public static List<Message> getMessagesByFolder() throws Exception {
    // Ensure client isn't null
    if (_appClient == null) {
      throw new Exception("Graph has not been initialized for user auth");
    }
    return getMessagesByFolder("inbox");
  }

  public static List<Message> getMessagesByFolder(String folderName) throws Exception {
    // Ensure client isn't null
    if (_appClient == null) {
      throw new Exception("Graph has not been initialized for user auth");
    }

    List<Message> messages = new ArrayList<>();
    final int top = 10;
    AtomicInteger skip = new AtomicInteger(0);
    while (true) {
      MessageCollectionResponse page = _appClient.users().byUserId(SHARED_INBOX_USER_ID)
          .mailFolders().byMailFolderId("inbox").messages().get(requestConfig -> {
            requestConfig.queryParameters.select =
                new String[] {"from", "isRead", "receivedDateTime", "subject", "body"};
            requestConfig.queryParameters.top = top;
            requestConfig.queryParameters.skip = skip.get();
            requestConfig.queryParameters.orderby = new String[] {"receivedDateTime DESC"};
          });
      if (page == null || page.getValue() == null || page.getValue().isEmpty()) {
        break;
      } else {
        messages.addAll(page.getValue());
        skip.addAndGet(top);
      }
    }
    return messages;
  }



}
