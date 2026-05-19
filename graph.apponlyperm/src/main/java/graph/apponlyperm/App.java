package graph.apponlyperm;

import java.io.IOException;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.FormatStyle;
import java.util.InputMismatchException;
import java.util.List;
import java.util.Properties;
import java.util.Scanner;
import org.jsoup.Jsoup;
import com.microsoft.graph.models.ItemBody;
import com.microsoft.graph.models.MailFolder;
import com.microsoft.graph.models.Message;
import com.microsoft.graph.models.User;
import com.microsoft.graph.models.UserCollectionResponse;

public class App {

  public static void main(String[] args) {
    System.out.println("Java App-Only Graph Tutorial");
    System.out.println();

    final Properties oAuthProperties = new Properties();
    try {
      oAuthProperties.load(App.class.getResourceAsStream("/oAuth.properties"));
    } catch (IOException e) {
      System.out.println(
          "Unable to read OAuth configuration. Make sure you have a properly formatted oAuth.properties file. See README for details.");
      return;
    }

    initializeGraph(oAuthProperties);

//    Scanner input = new Scanner(System.in);

//    int choice = -1;

//    while (choice != 0) {
//      System.out.println("Please choose one of the following options:");
//      System.out.println("0. Exit");
//      System.out.println("1. Display access token");
//      System.out.println("2. List users");
//      System.out.println("3. List Emails from shared inbox");
//      System.out.println("4. List Mail Folders from shared inbox");

//      try {
//        choice = input.nextInt();
//      } catch (InputMismatchException ex) {
//         Skip over non-integer input
//      }

//      input.nextLine();

      // Process user choice
//      switch (choice) {
//        case 0:
//          // Exit the program
//          System.out.println("Goodbye...");
//          break;
//        case 1:
//          // Display access token
//          displayAccessToken();
//          break;
//        case 2:
//          // List users
//          listUsers();
//          break;
//        case 3:
//          // List emails from user's inbox
          listInbox();
//          break;
//        case 4:
//          // List mail folders in user's outlook
//          listMailFolders();
//          break;

//        default:
//          System.out.println("Invalid choice");
//      }
//    }

//    input.close();
  }

  private static void initializeGraph(Properties properties) {
    try {
      Graph.initializeGraphForAppOnlyAuth(properties);
    } catch (Exception e) {
      System.out.println("Error initializing Graph for user auth");
      System.out.println(e.getMessage());
    }
  }

  private static void displayAccessToken() {
    try {
      final String accessToken = Graph.getAppOnlyToken();
      System.out.println("Access token: " + accessToken);
    } catch (Exception e) {
      System.out.println("Error getting access token: " + e.getMessage());
    }
  }

  private static void listUsers() {
    try {
      final UserCollectionResponse users = Graph.getUsers();

      // Output each user's details
      for (User user : users.getValue()) {
        System.out.println("User: " + user.getDisplayName());
        System.out.println("  ID: " + user.getId());
        System.out.println("  Email: " + user.getMail());
      }

      final Boolean moreUsersAvailable = users.getOdataNextLink() != null;
      System.out.println("\nMore users available? " + moreUsersAvailable);
    } catch (Exception e) {
      System.out.println("Error getting users");
      System.out.println(e.getMessage());
    }
  }

  private static void listMailFolders() {
    try {
      final List<MailFolder> mailFolders = Graph.getMailFolders();
      System.out.println("Total Mail Folders: " + mailFolders.size());
      for (MailFolder mailFolder : mailFolders) {
        System.out.println("Id: " + mailFolder.getId());
        System.out.println("  Display Name: " + mailFolder.getDisplayName());
      }
    } catch (Exception e) {
      System.out.println("Error getting mail folders");
      System.out.println(e.getMessage());
    }
  }

  private static void listInbox() {
    try {
      final List<Message> messages = Graph.getMessagesByFolder();
      // Output each message's details
      for (Message message : messages) {
        System.out.println("Message: " + message.getSubject());
        System.out.println("  From: " + message.getFrom().getEmailAddress().getName());
        System.out.println("  Status: " + (message.getIsRead() ? "Read" : "Unread"));
        System.out.println("  Received: " + message.getReceivedDateTime()
            // Values are returned in UTC, convert to local time zone
            .atZoneSameInstant(ZoneId.systemDefault()).toLocalDateTime()
            .format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT)));
        ItemBody body = message.getBody();
        String bodyPreview = message.getBodyPreview();
        if (body != null) {
          String bodyContent = body.getContent();
          if (bodyContent != null) {
            System.out.println("  Body: " + Jsoup.parse(bodyContent).text());
          }
        } else if (bodyPreview != null) {
          System.out.println("  Body Preview: " + Jsoup.parse(bodyPreview).text());
        } else {
          System.out.println("  Body: NONE");
        }
      }
    } catch (Exception e) {
      System.out.println("Error getting inbox");
      System.out.println(e.getMessage());
    }
  }


}
